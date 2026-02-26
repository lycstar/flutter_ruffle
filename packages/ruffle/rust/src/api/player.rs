use crate::api::{alloc_player_id, with_players, PlayerEntry};
use crate::backends::{
    audio as audio_backend, navigator as navigator_backend, storage as storage_backend,
};
use ruffle_core::backend::navigator::NullExecutor;
use ruffle_core::config::Letterbox;
use ruffle_core::tag_utils::SwfMovie;

#[derive(Clone, Debug)]
pub struct SwfHeaderInfo {
    pub swf_version: u8,
    pub width_px: f64,
    pub height_px: f64,
    pub frame_rate: f64,
    pub num_frames: u16,
    pub compression: String,
    pub is_action_script_3: bool,
}

#[derive(Clone, Debug)]
pub struct PlayerTickResult {
    pub needs_render: bool,
    pub time_til_next_frame_millis: u64,
}

#[derive(Clone, Debug)]
pub struct RgbaFrame {
    pub width: u32,
    pub height: u32,
    pub rgba: Vec<u8>,
}

#[flutter_rust_bridge::frb(sync)]
pub fn version() -> String {
    env!("CARGO_PKG_VERSION").to_string()
}

fn swf_movie_header_info(movie: &SwfMovie) -> anyhow::Result<SwfHeaderInfo> {
    let header = movie.header();
    let stage = header.stage_size();

    let compression = match header.compression() {
        ruffle_core::swf::Compression::None => "None",
        ruffle_core::swf::Compression::Zlib => "Zlib",
        ruffle_core::swf::Compression::Lzma => "Lzma",
    }
    .to_string();

    Ok(SwfHeaderInfo {
        swf_version: header.version(),
        width_px: stage.width().to_pixels(),
        height_px: stage.height().to_pixels(),
        frame_rate: header.frame_rate().to_f64(),
        num_frames: header.num_frames(),
        compression,
        is_action_script_3: header.is_action_script_3(),
    })
}

#[flutter_rust_bridge::frb(sync)]
pub fn player_create_from_bytes_platform_surface(
    bytes: Vec<u8>,
    url: String,
    surface_ptr: u64,
    width: u32,
    height: u32,
    scale_factor: f64,
) -> anyhow::Result<u64> {
    with_players(move |map| {
        let _tokio = crate::api::init::enter_tokio();
        use ruffle_core::PlayerBuilder;
        use ruffle_render_wgpu::backend::WgpuRenderBackend;
        use ruffle_render_wgpu::target::SwapChainTarget;
        use ruffle_render_wgpu::wgpu::SurfaceTargetUnsafe;
        use std::ffi::c_void;

        if surface_ptr == 0 {
            return Err(anyhow::anyhow!("surface_ptr is null"));
        }

        let movie = SwfMovie::from_data(bytes.as_slice(), url.clone(), None)?;
        let header = swf_movie_header_info(&movie)?;

        let width = width.max(1);
        let height = height.max(1);
        let scale_factor = if scale_factor.is_finite() && scale_factor > 0.0 {
            scale_factor
        } else {
            1.0
        };

        let surface_target = unsafe {
            #[cfg(any(target_os = "macos", target_os = "ios"))]
            {
                SurfaceTargetUnsafe::CoreAnimationLayer(surface_ptr as *mut c_void)
            }

            #[cfg(target_os = "android")]
            {
                use raw_window_handle::{
                    AndroidDisplayHandle, AndroidNdkWindowHandle, RawDisplayHandle, RawWindowHandle,
                };
                use std::ptr::NonNull;

                let window = NonNull::new(surface_ptr as *mut c_void)
                    .ok_or_else(|| anyhow::anyhow!("surface_ptr is null"))?;
                let raw_window_handle =
                    RawWindowHandle::AndroidNdk(AndroidNdkWindowHandle::new(window));
                let raw_display_handle = RawDisplayHandle::Android(AndroidDisplayHandle::new());
                SurfaceTargetUnsafe::RawHandle {
                    raw_display_handle,
                    raw_window_handle,
                }
            }

            #[cfg(not(any(target_os = "macos", target_os = "ios", target_os = "android")))]
            {
                return Err(anyhow::anyhow!(
                    "platform surface is not supported on this target"
                ));
            }
        };

        let renderer = unsafe {
            WgpuRenderBackend::<SwapChainTarget>::for_window_unsafe(
                surface_target,
                (width, height),
                #[cfg(target_os = "android")]
                ruffle_render_wgpu::wgpu::Backends::GL,
                #[cfg(not(target_os = "android"))]
                ruffle_render_wgpu::wgpu::Backends::PRIMARY,
                ruffle_render_wgpu::wgpu::PowerPreference::HighPerformance,
            )
        }
        .map_err(|e| anyhow::anyhow!(e.to_string()))?;

        let audio = audio_backend::make_audio_backend();
        let navigator_executor = NullExecutor::new();
        let navigator = navigator_backend::make_navigator_backend(&url, &navigator_executor);
        let storage = storage_backend::make_storage_backend(&url);

        let player = PlayerBuilder::new()
            .with_movie(movie)
            .with_boxed_audio(audio)
            .with_navigator(navigator)
            .with_storage(storage)
            .with_renderer(renderer)
            .with_viewport_dimensions(width, height, scale_factor)
            .with_autoplay(true)
            .build();
        {
            let mut player_lock = player.lock().unwrap();
            player_lock.set_letterbox(Letterbox::On);
            player_lock.set_is_playing(true);
        }

        let player_id = alloc_player_id();
        map.insert(
            player_id,
            PlayerEntry {
                player,
                header,
                navigator_executor,
            },
        );
        Ok(player_id)
    })
}

#[flutter_rust_bridge::frb(sync)]
/// 创建离屏渲染模式的 player（用于 Windows/Linux 等没有平台 Surface 的 Flutter 端）。
pub fn player_create_from_bytes_offscreen(
    bytes: Vec<u8>,
    url: String,
    width: u32,
    height: u32,
    scale_factor: f64,
) -> anyhow::Result<u64> {
    with_players(move |map| {
        let _tokio = crate::api::init::enter_tokio();
        use ruffle_core::PlayerBuilder;
        use ruffle_render_wgpu::backend::WgpuRenderBackend;
        use ruffle_render_wgpu::target::TextureTarget;
        use ruffle_render_wgpu::wgpu;

        let movie = SwfMovie::from_data(bytes.as_slice(), url.clone(), None)?;
        let header = swf_movie_header_info(&movie)?;

        let width = width.max(1);
        let height = height.max(1);
        let scale_factor = if scale_factor.is_finite() && scale_factor > 0.0 {
            scale_factor
        } else {
            1.0
        };

        let renderer = WgpuRenderBackend::<TextureTarget>::for_offscreen(
            (width, height),
            wgpu::Backends::PRIMARY,
            wgpu::PowerPreference::HighPerformance,
        )
        .map_err(|e| anyhow::anyhow!(e.to_string()))?;

        let audio = audio_backend::make_audio_backend();
        let navigator_executor = NullExecutor::new();
        let navigator = navigator_backend::make_navigator_backend(&url, &navigator_executor);
        let storage = storage_backend::make_storage_backend(&url);

        let player = PlayerBuilder::new()
            .with_movie(movie)
            .with_boxed_audio(audio)
            .with_navigator(navigator)
            .with_storage(storage)
            .with_renderer(renderer)
            .with_viewport_dimensions(width, height, scale_factor)
            .with_autoplay(true)
            .build();
        {
            let mut player_lock = player.lock().unwrap();
            player_lock.set_letterbox(Letterbox::On);
            player_lock.set_is_playing(true);
        }

        let player_id = alloc_player_id();
        map.insert(
            player_id,
            PlayerEntry {
                player,
                header,
                navigator_executor,
            },
        );
        Ok(player_id)
    })
}

#[flutter_rust_bridge::frb(sync)]
pub fn player_get_header(player_id: u64) -> anyhow::Result<SwfHeaderInfo> {
    with_players(move |map| {
        map.get(&player_id)
            .map(|e| e.header.clone())
            .ok_or_else(|| anyhow::anyhow!("player not found: {player_id}"))
    })
}

#[flutter_rust_bridge::frb(sync)]
pub fn player_total_frames(player_id: u64) -> anyhow::Result<u16> {
    with_players(move |map| {
        let entry = map
            .get(&player_id)
            .ok_or_else(|| anyhow::anyhow!("player not found: {player_id}"))?;
        Ok(entry.header.num_frames)
    })
}

#[flutter_rust_bridge::frb(sync)]
/// 推进 player 一次，并返回本次 tick 的渲染需求/下一帧时间。
pub fn player_tick(player_id: u64, dt_millis: f64) -> anyhow::Result<PlayerTickResult> {
    with_players(move |map| {
        let _tokio = crate::api::init::enter_tokio();
        let entry = map
            .get_mut(&player_id)
            .ok_or_else(|| anyhow::anyhow!("player not found: {player_id}"))?;

        {
            let mut player_lock = entry.player.lock().unwrap();
            player_lock.tick(dt_millis);
        }

        entry.navigator_executor.run();

        let player_lock = entry.player.lock().unwrap();
        Ok(PlayerTickResult {
            needs_render: player_lock.needs_render(),
            time_til_next_frame_millis: player_lock.time_til_next_frame().as_millis() as u64,
        })
    })
}

#[flutter_rust_bridge::frb(sync)]
pub fn player_render_present(player_id: u64) -> anyhow::Result<()> {
    let _tokio = crate::api::init::enter_tokio();
    with_players(move |map| {
        let entry = map
            .get(&player_id)
            .ok_or_else(|| anyhow::anyhow!("player not found: {player_id}"))?;

        let mut player_lock = entry.player.lock().unwrap();
        player_lock.render();
        Ok(())
    })
}

#[flutter_rust_bridge::frb(sync)]
/// 将当前画面渲染到离屏纹理并抓取 RGBA 像素（宽高随当前 viewport 变化）。
pub fn player_render_capture_rgba(player_id: u64) -> anyhow::Result<RgbaFrame> {
    let _tokio = crate::api::init::enter_tokio();
    use ruffle_render_wgpu::backend::WgpuRenderBackend;
    use ruffle_render_wgpu::target::TextureTarget;
    use std::any::Any;

    with_players(move |map| {
        let entry = map
            .get(&player_id)
            .ok_or_else(|| anyhow::anyhow!("player not found: {player_id}"))?;

        let mut player_lock = entry.player.lock().unwrap();
        player_lock.render();

        let renderer = player_lock.renderer_mut();
        let renderer_any = renderer as &mut dyn Any;
        let wgpu_renderer = renderer_any
            .downcast_mut::<WgpuRenderBackend<TextureTarget>>()
            .ok_or_else(|| anyhow::anyhow!("renderer is not offscreen wgpu backend"))?;

        let image = wgpu_renderer
            .capture_frame()
            .ok_or_else(|| anyhow::anyhow!("capture_frame returned None"))?;
        let (width, height) = image.dimensions();
        Ok(RgbaFrame {
            width,
            height,
            rgba: image.into_raw(),
        })
    })
}

#[flutter_rust_bridge::frb(sync)]
/// 用新的平台 surface 指针重建 wgpu surface（用于 Android 前后台或窗口重建导致的 surface 失效/变化）。
pub fn player_recreate_surface_platform_surface(
    player_id: u64,
    surface_ptr: u64,
    width: u32,
    height: u32,
) -> anyhow::Result<()> {
    use ruffle_render_wgpu::backend::WgpuRenderBackend;
    use ruffle_render_wgpu::target::SwapChainTarget;
    use ruffle_render_wgpu::wgpu::SurfaceTargetUnsafe;
    use std::any::Any;
    use std::ffi::c_void;

    if surface_ptr == 0 {
        return Err(anyhow::anyhow!("surface_ptr is null"));
    }

    let width = width.max(1);
    let height = height.max(1);

    with_players(move |map| {
        let _tokio = crate::api::init::enter_tokio();
        let entry = map
            .get(&player_id)
            .ok_or_else(|| anyhow::anyhow!("player not found: {player_id}"))?;

        let mut player_lock = entry.player.lock().unwrap();
        let renderer = <dyn Any>::downcast_mut::<WgpuRenderBackend<SwapChainTarget>>(
            player_lock.renderer_mut(),
        )
        .ok_or_else(|| anyhow::anyhow!("renderer is not WgpuRenderBackend<SwapChainTarget>"))?;

        let surface_target = unsafe {
            #[cfg(any(target_os = "macos", target_os = "ios"))]
            {
                SurfaceTargetUnsafe::CoreAnimationLayer(surface_ptr as *mut c_void)
            }

            #[cfg(target_os = "android")]
            {
                use raw_window_handle::{
                    AndroidDisplayHandle, AndroidNdkWindowHandle, RawDisplayHandle,
                    RawWindowHandle,
                };
                use std::ptr::NonNull;

                let window = NonNull::new(surface_ptr as *mut c_void)
                    .ok_or_else(|| anyhow::anyhow!("surface_ptr is null"))?;
                let raw_window_handle =
                    RawWindowHandle::AndroidNdk(AndroidNdkWindowHandle::new(window));
                let raw_display_handle = RawDisplayHandle::Android(AndroidDisplayHandle::new());
                SurfaceTargetUnsafe::RawHandle {
                    raw_display_handle,
                    raw_window_handle,
                }
            }

            #[cfg(not(any(target_os = "macos", target_os = "ios", target_os = "android")))]
            {
                return Err(anyhow::anyhow!(
                    "platform surface is not supported on this target"
                ));
            }
        };

        unsafe { renderer.recreate_surface_unsafe(surface_target, (width, height)) }
            .map_err(|e| anyhow::anyhow!(e.to_string()))?;
        Ok(())
    })
}

#[flutter_rust_bridge::frb(sync)]
pub fn player_dispose(player_id: u64) -> bool {
    with_players(move |map| map.remove(&player_id).is_some())
}
