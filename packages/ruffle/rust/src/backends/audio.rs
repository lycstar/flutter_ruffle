use ruffle_core::backend::audio::{AudioBackend, NullAudioBackend};
#[cfg(not(target_os = "android"))]
use ruffle_frontend_utils::backends::audio::CpalAudioBackend;

/// 构建音频后端：
/// - 优先使用 ruffle_frontend_utils 提供的 CPAL 音频后端（跨平台）。
/// - 若初始化失败则回退到 NullAudioBackend（静音但不中断播放）。
pub(crate) fn make_audio_backend() -> Box<dyn AudioBackend> {
    #[cfg(target_os = "android")]
    {
        match AAudioAudioBackend::new() {
            Ok(backend) => Box::new(backend),
            Err(_) => Box::new(NullAudioBackend::new()),
        }
    }

    #[cfg(not(target_os = "android"))]
    match CpalAudioBackend::new(None) {
        Ok(backend) => Box::new(backend),
        Err(_) => Box::new(NullAudioBackend::new()),
    }
}

#[cfg(target_os = "android")]
mod android_aaudio {
    use ndk::audio::{
        AudioCallbackResult, AudioDirection, AudioError, AudioFormat, AudioPerformanceMode,
        AudioStream, AudioStreamBuilder, AudioStreamState,
    };
    use ruffle_core::backend::audio::{
        swf, AudioBackend, AudioMixer, DecodeError, RegisterError, SoundHandle,
        SoundInstanceHandle, SoundStreamInfo, SoundTransform,
    };
    use ruffle_core::impl_audio_mixer_backend;
    use std::sync::{
        atomic::{AtomicBool, Ordering},
        Arc,
    };

    pub struct AAudioAudioBackend {
        stream: Option<AudioStream>,
        mixer: AudioMixer,
        paused: bool,
        sample_rate: i32,
        format: AudioFormat,
        recreate_requested: Arc<AtomicBool>,
    }

    type Error = Box<dyn std::error::Error>;

    impl AAudioAudioBackend {
        /// 创建 Android AAudio 音频后端：
        /// - 优先使用 44100Hz（与 ruffle-android 一致）
        /// - 若设备不支持则回退 48000Hz
        pub fn new() -> Result<Self, Error> {
            let recreate_requested = Arc::new(AtomicBool::new(false));
            let mut last_err: Option<Error> = None;

            for (sample_rate, format) in [
                (44100_i32, AudioFormat::PCM_Float),
                (44100_i32, AudioFormat::PCM_I16),
                (48000_i32, AudioFormat::PCM_Float),
                (48000_i32, AudioFormat::PCM_I16),
            ] {
                let mixer = AudioMixer::new(2, sample_rate as u32);
                match Self::open_stream(
                    mixer.proxy(),
                    recreate_requested.clone(),
                    sample_rate,
                    format,
                ) {
                    Ok(stream) => {
                        return Ok(Self {
                            stream: Some(stream),
                            mixer,
                            paused: true,
                            sample_rate,
                            format,
                            recreate_requested,
                        });
                    }
                    Err(e) => last_err = Some(e),
                }
            }

            Err(last_err.unwrap_or_else(|| "AAudio 打开输出流失败".into()))
        }

        /// 打开一个新的 AAudio 输出流，并接入 AudioMixer。
        fn open_stream(
            proxy: ruffle_core::backend::audio::AudioMixerProxy,
            recreate_requested: Arc<AtomicBool>,
            sample_rate: i32,
            format: AudioFormat,
        ) -> Result<AudioStream, Error> {
            let data_callback = Box::new(
                move |_stream: &AudioStream, data: *mut std::ffi::c_void, len: i32| {
                    match format {
                        AudioFormat::PCM_Float => {
                            let sl = unsafe {
                                std::slice::from_raw_parts_mut::<f32>(
                                    data as *mut f32,
                                    len as usize * 2,
                                )
                            };
                            proxy.mix(sl);
                        }
                        AudioFormat::PCM_I16 => {
                            let sl = unsafe {
                                std::slice::from_raw_parts_mut::<i16>(
                                    data as *mut i16,
                                    len as usize * 2,
                                )
                            };
                            proxy.mix(sl);
                        }
                        _ => return AudioCallbackResult::Stop,
                    }

                    AudioCallbackResult::Continue
                },
            );

            let error_flag = recreate_requested.clone();
            let error_callback = Box::new(move |_stream: &AudioStream, err: AudioError| {
                if matches!(err, AudioError::Disconnected) {
                    error_flag.store(true, Ordering::Release);
                }
            });

            Ok(AudioStreamBuilder::new()?
                .direction(AudioDirection::Output)
                .format(format)
                .channel_count(2)
                .sample_rate(sample_rate)
                .performance_mode(AudioPerformanceMode::LowLatency)
                .data_callback(data_callback)
                .error_callback(error_callback)
                .open_stream()?)
        }

        /// 在需要时（断开设备 / 错误回调）重建输出流。
        fn recreate_stream_if_needed(&mut self) {
            if self
                .recreate_requested
                .compare_exchange(true, false, Ordering::AcqRel, Ordering::Acquire)
                .is_ok()
            {
                self.stream = None;
            };

            let disconnected = self
                .stream
                .as_ref()
                .is_some_and(|stream| stream.state() == AudioStreamState::Disconnected);

            if disconnected {
                self.stream = None;
            }

            if self.stream.is_none() {
                if let Ok(stream) = Self::open_stream(
                    self.mixer.proxy(),
                    self.recreate_requested.clone(),
                    self.sample_rate,
                    self.format,
                ) {
                    if !self.paused {
                        let _ = stream.request_start();
                    }
                    self.stream = Some(stream);
                }
            }
        }

        /// 尝试启动播放。对 `InvalidState` 做容错处理（AAudio 的 start 是异步的）。
        fn try_start(&mut self) {
            self.recreate_stream_if_needed();

            let Some(stream) = self.stream.as_ref() else {
                return;
            };
            match stream.request_start() {
                Ok(()) | Err(AudioError::InvalidState) => {}
                Err(AudioError::Disconnected) => {
                    self.recreate_requested.store(true, Ordering::Release);
                    self.recreate_stream_if_needed();
                    if let Some(stream) = self.stream.as_ref() {
                        let _ = stream.request_start();
                    }
                }
                Err(_) => {}
            }
        }
    }

    impl AudioBackend for AAudioAudioBackend {
        impl_audio_mixer_backend!(mixer);

        /// 开始/恢复音频输出。
        fn play(&mut self) {
            self.try_start();
            self.paused = false;
        }

        /// 暂停音频输出（若设备不支持 pause，则改为 stop）。
        fn pause(&mut self) {
            if let Some(stream) = self.stream.as_ref() {
                match stream.request_pause() {
                    Ok(()) | Err(AudioError::InvalidState) => {}
                    Err(AudioError::Unimplemented) => {
                        let _ = stream.request_stop();
                    }
                    Err(AudioError::Disconnected) => {
                        self.recreate_requested.store(true, Ordering::Release);
                    }
                    Err(_) => {}
                }
            }
            self.paused = true;
        }

        /// 每帧驱动音频后端做必要的重建/恢复。
        fn tick(&mut self) {
            self.recreate_stream_if_needed();
        }
    }
}

#[cfg(target_os = "android")]
use android_aaudio::AAudioAudioBackend;
