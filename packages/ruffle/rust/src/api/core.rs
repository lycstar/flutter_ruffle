use crate::api::with_players;
use ruffle_core::config::Letterbox;
use ruffle_core::{Color, PlayerEvent, StageScaleMode};
use ruffle_render::backend::ViewportDimensions as RuffleViewportDimensions;
use ruffle_render::quality::StageQuality;
use std::str::FromStr;

#[derive(Clone, Debug)]
pub struct ViewportDimensions {
    pub width: u32,
    pub height: u32,
    pub scale_factor: f64,
}

#[flutter_rust_bridge::frb(sync)]
/// 设置 player 的画质（可用值：low/medium/high/best/8x8/8x8linear/16x16/16x16linear）。
pub fn player_set_quality(player_id: u64, quality: String) -> anyhow::Result<()> {
    let quality = StageQuality::from_str(quality.trim())
        .map_err(|_| anyhow::anyhow!("invalid quality: {quality}"))?;
    with_players(move |map| {
        let entry = map
            .get(&player_id)
            .ok_or_else(|| anyhow::anyhow!("player not found: {player_id}"))?;
        let mut player_lock = entry.player.lock().unwrap();
        player_lock.set_quality(quality);
        Ok(())
    })
}

#[flutter_rust_bridge::frb(sync)]
/// 获取 player 当前画质（返回值同 Stage.quality：low/medium/high/best/8x8/...；对应 ruffle_core::Player::quality）。
pub fn player_quality(player_id: u64) -> anyhow::Result<String> {
    with_players(move |map| {
        let entry = map
            .get(&player_id)
            .ok_or_else(|| anyhow::anyhow!("player not found: {player_id}"))?;
        let mut player_lock = entry.player.lock().unwrap();
        Ok(player_lock.quality().to_string())
    })
}

#[flutter_rust_bridge::frb(sync)]
/// 获取 player 是否处于播放状态（对应 ruffle_core::Player::is_playing）。
pub fn player_is_playing(player_id: u64) -> anyhow::Result<bool> {
    with_players(move |map| {
        let entry = map
            .get(&player_id)
            .ok_or_else(|| anyhow::anyhow!("player not found: {player_id}"))?;
        let player_lock = entry.player.lock().unwrap();
        Ok(player_lock.is_playing())
    })
}

#[flutter_rust_bridge::frb(sync)]
/// 设置 player 播放状态（对应 ruffle_core::Player::set_is_playing）。
pub fn player_set_is_playing(player_id: u64, is_playing: bool) -> anyhow::Result<()> {
    with_players(move |map| {
        let entry = map
            .get(&player_id)
            .ok_or_else(|| anyhow::anyhow!("player not found: {player_id}"))?;
        let mut player_lock = entry.player.lock().unwrap();
        player_lock.set_is_playing(is_playing);
        Ok(())
    })
}

#[flutter_rust_bridge::frb(sync)]
/// 获取 player 主音量（范围通常为 0.0~1.0，对应 ruffle_core::Player::volume）。
pub fn player_volume(player_id: u64) -> anyhow::Result<f32> {
    with_players(move |map| {
        let entry = map
            .get(&player_id)
            .ok_or_else(|| anyhow::anyhow!("player not found: {player_id}"))?;
        let player_lock = entry.player.lock().unwrap();
        Ok(player_lock.volume())
    })
}

#[flutter_rust_bridge::frb(sync)]
/// 设置 player 主音量（范围通常为 0.0~1.0，对应 ruffle_core::Player::set_volume）。
pub fn player_set_volume(player_id: u64, volume: f32) -> anyhow::Result<()> {
    with_players(move |map| {
        let entry = map
            .get(&player_id)
            .ok_or_else(|| anyhow::anyhow!("player not found: {player_id}"))?;
        let mut player_lock = entry.player.lock().unwrap();
        player_lock.set_volume(volume);
        Ok(())
    })
}

#[flutter_rust_bridge::frb(sync)]
/// 获取 player 是否为全屏状态（对应 ruffle_core::Player::is_fullscreen）。
pub fn player_is_fullscreen(player_id: u64) -> anyhow::Result<bool> {
    with_players(move |map| {
        let entry = map
            .get(&player_id)
            .ok_or_else(|| anyhow::anyhow!("player not found: {player_id}"))?;
        let mut player_lock = entry.player.lock().unwrap();
        Ok(player_lock.is_fullscreen())
    })
}

#[flutter_rust_bridge::frb(sync)]
/// 设置 player 全屏状态（对应 ruffle_core::Player::set_fullscreen）。
pub fn player_set_fullscreen(player_id: u64, is_fullscreen: bool) -> anyhow::Result<()> {
    with_players(move |map| {
        let entry = map
            .get(&player_id)
            .ok_or_else(|| anyhow::anyhow!("player not found: {player_id}"))?;
        let mut player_lock = entry.player.lock().unwrap();
        player_lock.set_fullscreen(is_fullscreen);
        Ok(())
    })
}

#[flutter_rust_bridge::frb(sync)]
/// 设置是否允许 SWF 进入全屏（对应 ruffle_core::Player::set_allow_fullscreen）。
pub fn player_set_allow_fullscreen(player_id: u64, allow_fullscreen: bool) -> anyhow::Result<()> {
    with_players(move |map| {
        let entry = map
            .get(&player_id)
            .ok_or_else(|| anyhow::anyhow!("player not found: {player_id}"))?;
        let mut player_lock = entry.player.lock().unwrap();
        player_lock.set_allow_fullscreen(allow_fullscreen);
        Ok(())
    })
}

#[flutter_rust_bridge::frb(sync)]
/// 获取 letterbox 配置（off/fullscreen/on，对应 ruffle_core::Player::letterbox）。
pub fn player_letterbox(player_id: u64) -> anyhow::Result<String> {
    with_players(move |map| {
        let entry = map
            .get(&player_id)
            .ok_or_else(|| anyhow::anyhow!("player not found: {player_id}"))?;
        let mut player_lock = entry.player.lock().unwrap();
        Ok(player_lock.letterbox().to_string())
    })
}

#[flutter_rust_bridge::frb(sync)]
/// 设置 letterbox 配置（off/fullscreen/on，对应 ruffle_core::Player::set_letterbox）。
pub fn player_set_letterbox(player_id: u64, letterbox: String) -> anyhow::Result<()> {
    let letterbox = Letterbox::from_str(letterbox.trim())
        .map_err(|_| anyhow::anyhow!("invalid letterbox: {letterbox}"))?;
    with_players(move |map| {
        let entry = map
            .get(&player_id)
            .ok_or_else(|| anyhow::anyhow!("player not found: {player_id}"))?;
        let mut player_lock = entry.player.lock().unwrap();
        player_lock.set_letterbox(letterbox);
        Ok(())
    })
}

#[flutter_rust_bridge::frb(sync)]
/// 获取舞台背景色（AARRGGBB），None 表示使用 SWF 默认背景（对应 ruffle_core::Player::background_color）。
pub fn player_background_color(player_id: u64) -> anyhow::Result<Option<u32>> {
    with_players(move |map| {
        let entry = map
            .get(&player_id)
            .ok_or_else(|| anyhow::anyhow!("player not found: {player_id}"))?;
        let mut player_lock = entry.player.lock().unwrap();
        Ok(player_lock.background_color().map(|c| c.to_rgba()))
    })
}

#[flutter_rust_bridge::frb(sync)]
/// 设置舞台背景色（AARRGGBB），None 表示清空并回退到 SWF 默认背景（对应 ruffle_core::Player::set_background_color）。
pub fn player_set_background_color(player_id: u64, argb: Option<u32>) -> anyhow::Result<()> {
    with_players(move |map| {
        let entry = map
            .get(&player_id)
            .ok_or_else(|| anyhow::anyhow!("player not found: {player_id}"))?;
        let mut player_lock = entry.player.lock().unwrap();
        player_lock.set_background_color(argb.map(Color::from_rgba));
        Ok(())
    })
}

#[flutter_rust_bridge::frb(sync)]
/// 获取当前 movie 的 frame rate（FPS，对应 ruffle_core::Player::frame_rate）。
pub fn player_frame_rate(player_id: u64) -> anyhow::Result<f64> {
    with_players(move |map| {
        let entry = map
            .get(&player_id)
            .ok_or_else(|| anyhow::anyhow!("player not found: {player_id}"))?;
        let player_lock = entry.player.lock().unwrap();
        Ok(player_lock.frame_rate())
    })
}

#[flutter_rust_bridge::frb(sync)]
/// 获取主时间轴当前帧（1-based，可能为 None；对应 ruffle_core::Player::current_frame）。
pub fn player_current_frame(player_id: u64) -> anyhow::Result<Option<u16>> {
    with_players(move |map| {
        let entry = map
            .get(&player_id)
            .ok_or_else(|| anyhow::anyhow!("player not found: {player_id}"))?;
        let player_lock = entry.player.lock().unwrap();
        Ok(player_lock.current_frame())
    })
}

#[flutter_rust_bridge::frb(sync)]
/// 获取当前 movie 的舞台逻辑尺寸（像素，对应 ruffle_core::Player::movie_width）。
pub fn player_movie_width(player_id: u64) -> anyhow::Result<u32> {
    with_players(move |map| {
        let entry = map
            .get(&player_id)
            .ok_or_else(|| anyhow::anyhow!("player not found: {player_id}"))?;
        let mut player_lock = entry.player.lock().unwrap();
        Ok(player_lock.movie_width())
    })
}

#[flutter_rust_bridge::frb(sync)]
/// 获取当前 movie 的舞台逻辑尺寸（像素，对应 ruffle_core::Player::movie_height）。
pub fn player_movie_height(player_id: u64) -> anyhow::Result<u32> {
    with_players(move |map| {
        let entry = map
            .get(&player_id)
            .ok_or_else(|| anyhow::anyhow!("player not found: {player_id}"))?;
        let mut player_lock = entry.player.lock().unwrap();
        Ok(player_lock.movie_height())
    })
}

#[flutter_rust_bridge::frb(sync)]
/// 获取当前 viewport 信息（物理像素 + scale_factor，对应 ruffle_core::Player::viewport_dimensions）。
pub fn player_viewport_dimensions(player_id: u64) -> anyhow::Result<ViewportDimensions> {
    with_players(move |map| {
        let entry = map
            .get(&player_id)
            .ok_or_else(|| anyhow::anyhow!("player not found: {player_id}"))?;
        let mut player_lock = entry.player.lock().unwrap();
        let dims = player_lock.viewport_dimensions();
        Ok(ViewportDimensions {
            width: dims.width,
            height: dims.height,
            scale_factor: dims.scale_factor,
        })
    })
}

#[flutter_rust_bridge::frb(sync)]
/// 设置 player 的 viewport（width/height 为物理像素；scale_factor 通常为设备 DPR）。
pub fn player_set_viewport_dimensions(
    player_id: u64,
    width: u32,
    height: u32,
    scale_factor: f64,
) -> anyhow::Result<()> {
    let dimensions = RuffleViewportDimensions {
        width: width.max(1),
        height: height.max(1),
        scale_factor: if scale_factor.is_finite() && scale_factor > 0.0 {
            scale_factor
        } else {
            1.0
        },
    };
    with_players(move |map| {
        let entry = map
            .get(&player_id)
            .ok_or_else(|| anyhow::anyhow!("player not found: {player_id}"))?;
        let mut player_lock = entry.player.lock().unwrap();
        player_lock.set_viewport_dimensions(dimensions);
        Ok(())
    })
}

#[flutter_rust_bridge::frb(sync)]
/// 设置 player 的缩放模式（exact_fit/no_border/no_scale/show_all）。
pub fn player_set_scale_mode(player_id: u64, scale_mode: String) -> anyhow::Result<()> {
    let scale_mode = StageScaleMode::from_str(scale_mode.trim())
        .map_err(|_| anyhow::anyhow!("invalid scale_mode: {scale_mode}"))?;
    with_players(move |map| {
        let entry = map
            .get(&player_id)
            .ok_or_else(|| anyhow::anyhow!("player not found: {player_id}"))?;
        let mut player_lock = entry.player.lock().unwrap();
        player_lock.set_scale_mode(scale_mode);
        Ok(())
    })
}

#[flutter_rust_bridge::frb(sync)]
/// 获取 player 当前缩放模式（exact_fit/no_border/no_scale/show_all）。
pub fn player_scale_mode(player_id: u64) -> anyhow::Result<String> {
    with_players(move |map| {
        let entry = map
            .get(&player_id)
            .ok_or_else(|| anyhow::anyhow!("player not found: {player_id}"))?;
        let mut player_lock = entry.player.lock().unwrap();
        Ok(player_lock.scale_mode().to_string())
    })
}

#[flutter_rust_bridge::frb(sync)]
/// 获取 player 是否强制缩放模式（对应 ruffle_core::Player::forced_scale_mode）。
pub fn player_forced_scale_mode(player_id: u64) -> anyhow::Result<bool> {
    with_players(move |map| {
        let entry = map
            .get(&player_id)
            .ok_or_else(|| anyhow::anyhow!("player not found: {player_id}"))?;
        let mut player_lock = entry.player.lock().unwrap();
        Ok(player_lock.forced_scale_mode())
    })
}

#[flutter_rust_bridge::frb(sync)]
/// 设置是否强制缩放模式（对应 ruffle_core::Player::set_forced_scale_mode）。
pub fn player_set_forced_scale_mode(player_id: u64, force: bool) -> anyhow::Result<()> {
    with_players(move |map| {
        let entry = map
            .get(&player_id)
            .ok_or_else(|| anyhow::anyhow!("player not found: {player_id}"))?;
        let mut player_lock = entry.player.lock().unwrap();
        player_lock.set_forced_scale_mode(force);
        Ok(())
    })
}

#[flutter_rust_bridge::frb(sync)]
/// 设置 player 的 window_mode（字符串：window/opaque/transparent 等；对应 ruffle_core::Player::set_window_mode）。
pub fn player_set_window_mode(player_id: u64, window_mode: String) -> anyhow::Result<()> {
    with_players(move |map| {
        let entry = map
            .get(&player_id)
            .ok_or_else(|| anyhow::anyhow!("player not found: {player_id}"))?;
        let mut player_lock = entry.player.lock().unwrap();
        player_lock.set_window_mode(window_mode.trim());
        Ok(())
    })
}

#[flutter_rust_bridge::frb(sync)]
/// 设置是否显示右键菜单（对应 ruffle_core::Player::set_show_menu）。
pub fn player_set_show_menu(player_id: u64, show_menu: bool) -> anyhow::Result<()> {
    with_players(move |map| {
        let entry = map
            .get(&player_id)
            .ok_or_else(|| anyhow::anyhow!("player not found: {player_id}"))?;
        let mut player_lock = entry.player.lock().unwrap();
        player_lock.set_show_menu(show_menu);
        Ok(())
    })
}

#[flutter_rust_bridge::frb(sync)]
/// 指示 player 在下一帧后暂停（对应 ruffle_core::Player::suspend_after_next_frame）。
pub fn player_suspend_after_next_frame(player_id: u64) -> anyhow::Result<()> {
    with_players(move |map| {
        let entry = map
            .get(&player_id)
            .ok_or_else(|| anyhow::anyhow!("player not found: {player_id}"))?;
        let mut player_lock = entry.player.lock().unwrap();
        player_lock.suspend_after_next_frame();
        Ok(())
    })
}

#[flutter_rust_bridge::frb(sync)]
/// 获取 player 当前鼠标是否处于舞台内（对应 ruffle_core::Player::mouse_in_stage）。
pub fn player_mouse_in_stage(player_id: u64) -> anyhow::Result<bool> {
    with_players(move |map| {
        let entry = map
            .get(&player_id)
            .ok_or_else(|| anyhow::anyhow!("player not found: {player_id}"))?;
        let player_lock = entry.player.lock().unwrap();
        Ok(player_lock.mouse_in_stage())
    })
}

#[flutter_rust_bridge::frb(sync)]
/// 获取到下一帧的近似剩余时间（毫秒，对应 ruffle_core::Player::time_til_next_frame）。
pub fn player_time_til_next_frame(player_id: u64) -> anyhow::Result<u64> {
    with_players(move |map| {
        let entry = map
            .get(&player_id)
            .ok_or_else(|| anyhow::anyhow!("player not found: {player_id}"))?;
        let player_lock = entry.player.lock().unwrap();
        Ok(player_lock.time_til_next_frame().as_millis() as u64)
    })
}

#[flutter_rust_bridge::frb(sync)]
/// 向 player 注入鼠标移动事件（坐标单位为 viewport 物理像素）。
pub fn player_mouse_move(player_id: u64, x: f64, y: f64) -> anyhow::Result<bool> {
    with_players(move |map| {
        let entry = map
            .get(&player_id)
            .ok_or_else(|| anyhow::anyhow!("player not found: {player_id}"))?;
        let mut player_lock = entry.player.lock().unwrap();
        Ok(player_lock.handle_event(PlayerEvent::MouseMove { x, y }))
    })
}

/// 将上层传入的数字按钮编码映射为 Ruffle 的鼠标按钮枚举。
fn mouse_button_from_u8(v: u8) -> ruffle_core::events::MouseButton {
    match v {
        1 => ruffle_core::events::MouseButton::Right,
        2 => ruffle_core::events::MouseButton::Middle,
        _ => ruffle_core::events::MouseButton::Left,
    }
}

#[flutter_rust_bridge::frb(sync)]
/// 向 player 注入鼠标按下事件（坐标单位为 viewport 物理像素；button: 0=Left, 1=Right, 2=Middle；index 可为空）。
pub fn player_mouse_down(
    player_id: u64,
    x: f64,
    y: f64,
    button: u8,
    index: Option<u32>,
) -> anyhow::Result<bool> {
    let button = mouse_button_from_u8(button);
    let index = index.map(|v| v as usize);
    with_players(move |map| {
        let entry = map
            .get(&player_id)
            .ok_or_else(|| anyhow::anyhow!("player not found: {player_id}"))?;
        let mut player_lock = entry.player.lock().unwrap();
        Ok(player_lock.handle_event(PlayerEvent::MouseDown {
            x,
            y,
            button,
            index,
        }))
    })
}

#[flutter_rust_bridge::frb(sync)]
/// 向 player 注入鼠标抬起事件（button: 0=Left, 1=Right, 2=Middle）。
pub fn player_mouse_up(player_id: u64, x: f64, y: f64, button: u8) -> anyhow::Result<bool> {
    let button = mouse_button_from_u8(button);
    with_players(move |map| {
        let entry = map
            .get(&player_id)
            .ok_or_else(|| anyhow::anyhow!("player not found: {player_id}"))?;
        let mut player_lock = entry.player.lock().unwrap();
        Ok(player_lock.handle_event(PlayerEvent::MouseUp { x, y, button }))
    })
}

#[flutter_rust_bridge::frb(sync)]
/// 向 player 注入鼠标离开舞台事件。
pub fn player_mouse_leave(player_id: u64) -> anyhow::Result<bool> {
    with_players(move |map| {
        let entry = map
            .get(&player_id)
            .ok_or_else(|| anyhow::anyhow!("player not found: {player_id}"))?;
        let mut player_lock = entry.player.lock().unwrap();
        Ok(player_lock.handle_event(PlayerEvent::MouseLeave))
    })
}

#[flutter_rust_bridge::frb(sync)]
/// 设置鼠标指针是否处于舞台内（用于正确处理悬停/按钮状态/拖拽等逻辑）。
pub fn player_set_mouse_in_stage(player_id: u64, is_in_stage: bool) -> anyhow::Result<()> {
    with_players(move |map| {
        let entry = map
            .get(&player_id)
            .ok_or_else(|| anyhow::anyhow!("player not found: {player_id}"))?;
        let mut player_lock = entry.player.lock().unwrap();
        player_lock.set_mouse_in_stage(is_in_stage);
        Ok(())
    })
}

#[flutter_rust_bridge::frb(sync)]
/// 通知 player 获得焦点（对齐桌面端 WindowEvent::Focused(true) 行为）。
pub fn player_focus_gained(player_id: u64) -> anyhow::Result<bool> {
    with_players(move |map| {
        let entry = map
            .get(&player_id)
            .ok_or_else(|| anyhow::anyhow!("player not found: {player_id}"))?;
        let mut player_lock = entry.player.lock().unwrap();
        Ok(player_lock.handle_event(PlayerEvent::FocusGained))
    })
}

#[flutter_rust_bridge::frb(sync)]
/// 通知 player 失去焦点（对齐桌面端 WindowEvent::Focused(false) 行为）。
pub fn player_focus_lost(player_id: u64) -> anyhow::Result<bool> {
    with_players(move |map| {
        let entry = map
            .get(&player_id)
            .ok_or_else(|| anyhow::anyhow!("player not found: {player_id}"))?;
        let mut player_lock = entry.player.lock().unwrap();
        Ok(player_lock.handle_event(PlayerEvent::FocusLost))
    })
}

#[flutter_rust_bridge::frb(sync)]
/// 向 player 注入鼠标滚轮事件（delta_pixels：像素单位，正负方向与上层保持一致）。
pub fn player_mouse_wheel_pixels(player_id: u64, delta_pixels: f64) -> anyhow::Result<bool> {
    let delta = ruffle_core::events::MouseWheelDelta::Pixels(delta_pixels);
    with_players(move |map| {
        let entry = map
            .get(&player_id)
            .ok_or_else(|| anyhow::anyhow!("player not found: {player_id}"))?;
        let mut player_lock = entry.player.lock().unwrap();
        Ok(player_lock.handle_event(PlayerEvent::MouseWheel { delta }))
    })
}

/// 将上层传入的逻辑按键字符串映射为 Ruffle 的逻辑按键枚举。
fn logical_key_from_str(s: &str) -> ruffle_core::events::LogicalKey {
    use ruffle_core::events::{LogicalKey, NamedKey};
    let mut chars = s.chars();
    let (c1, c2) = (chars.next(), chars.next());
    if let (Some(ch), None) = (c1, c2) {
        return LogicalKey::Character(ch);
    }
    let normalized = s.trim();
    match normalized {
        "Enter" => LogicalKey::Named(NamedKey::Enter),
        "Tab" => LogicalKey::Named(NamedKey::Tab),
        "Backspace" => LogicalKey::Named(NamedKey::Backspace),
        "Delete" => LogicalKey::Named(NamedKey::Delete),
        "Escape" => LogicalKey::Named(NamedKey::Escape),
        "ArrowLeft" => LogicalKey::Named(NamedKey::ArrowLeft),
        "ArrowRight" => LogicalKey::Named(NamedKey::ArrowRight),
        "ArrowUp" => LogicalKey::Named(NamedKey::ArrowUp),
        "ArrowDown" => LogicalKey::Named(NamedKey::ArrowDown),
        "Home" => LogicalKey::Named(NamedKey::Home),
        "End" => LogicalKey::Named(NamedKey::End),
        "PageUp" => LogicalKey::Named(NamedKey::PageUp),
        "PageDown" => LogicalKey::Named(NamedKey::PageDown),
        "Shift" | "ShiftLeft" | "ShiftRight" => LogicalKey::Named(NamedKey::Shift),
        "Control" | "ControlLeft" | "ControlRight" => LogicalKey::Named(NamedKey::Control),
        "Alt" | "AltLeft" | "AltRight" => LogicalKey::Named(NamedKey::Alt),
        "Super" | "SuperLeft" | "SuperRight" => LogicalKey::Named(NamedKey::Super),
        _ => LogicalKey::Unknown,
    }
}

/// 将上层传入的物理按键字符串映射为 Ruffle 的物理按键枚举。
fn physical_key_from_str(s: &str) -> ruffle_core::events::PhysicalKey {
    use ruffle_core::events::PhysicalKey;
    let normalized = s.trim();
    match normalized {
        "Enter" => PhysicalKey::Enter,
        "Tab" => PhysicalKey::Tab,
        "Backspace" => PhysicalKey::Backspace,
        "Delete" => PhysicalKey::Delete,
        "Escape" => PhysicalKey::Escape,
        "ArrowLeft" => PhysicalKey::ArrowLeft,
        "ArrowRight" => PhysicalKey::ArrowRight,
        "ArrowUp" => PhysicalKey::ArrowUp,
        "ArrowDown" => PhysicalKey::ArrowDown,
        "Home" => PhysicalKey::Home,
        "End" => PhysicalKey::End,
        "PageUp" => PhysicalKey::PageUp,
        "PageDown" => PhysicalKey::PageDown,
        "ShiftLeft" => PhysicalKey::ShiftLeft,
        "ShiftRight" => PhysicalKey::ShiftRight,
        "ControlLeft" => PhysicalKey::ControlLeft,
        "ControlRight" => PhysicalKey::ControlRight,
        "AltLeft" => PhysicalKey::AltLeft,
        "AltRight" => PhysicalKey::AltRight,
        "SuperLeft" => PhysicalKey::SuperLeft,
        "SuperRight" => PhysicalKey::SuperRight,
        " " => PhysicalKey::Space,
        _ => {
            if normalized.len() == 1 {
                let ch = normalized.chars().next().unwrap();
                if ch.is_ascii_alphabetic() {
                    return match ch.to_ascii_uppercase() {
                        'A' => PhysicalKey::KeyA,
                        'B' => PhysicalKey::KeyB,
                        'C' => PhysicalKey::KeyC,
                        'D' => PhysicalKey::KeyD,
                        'E' => PhysicalKey::KeyE,
                        'F' => PhysicalKey::KeyF,
                        'G' => PhysicalKey::KeyG,
                        'H' => PhysicalKey::KeyH,
                        'I' => PhysicalKey::KeyI,
                        'J' => PhysicalKey::KeyJ,
                        'K' => PhysicalKey::KeyK,
                        'L' => PhysicalKey::KeyL,
                        'M' => PhysicalKey::KeyM,
                        'N' => PhysicalKey::KeyN,
                        'O' => PhysicalKey::KeyO,
                        'P' => PhysicalKey::KeyP,
                        'Q' => PhysicalKey::KeyQ,
                        'R' => PhysicalKey::KeyR,
                        'S' => PhysicalKey::KeyS,
                        'T' => PhysicalKey::KeyT,
                        'U' => PhysicalKey::KeyU,
                        'V' => PhysicalKey::KeyV,
                        'W' => PhysicalKey::KeyW,
                        'X' => PhysicalKey::KeyX,
                        'Y' => PhysicalKey::KeyY,
                        'Z' => PhysicalKey::KeyZ,
                        _ => PhysicalKey::Unknown,
                    };
                }
                if ch.is_ascii_digit() {
                    return match ch {
                        '0' => PhysicalKey::Digit0,
                        '1' => PhysicalKey::Digit1,
                        '2' => PhysicalKey::Digit2,
                        '3' => PhysicalKey::Digit3,
                        '4' => PhysicalKey::Digit4,
                        '5' => PhysicalKey::Digit5,
                        '6' => PhysicalKey::Digit6,
                        '7' => PhysicalKey::Digit7,
                        '8' => PhysicalKey::Digit8,
                        '9' => PhysicalKey::Digit9,
                        _ => PhysicalKey::Unknown,
                    };
                }
            }
            PhysicalKey::Unknown
        }
    }
}

#[flutter_rust_bridge::frb(sync)]
/// 向 player 注入键盘按下事件（logical_key 支持单字符或常见键名，如 ArrowLeft/Enter）。
pub fn player_key_down(player_id: u64, logical_key: String) -> anyhow::Result<bool> {
    let key = ruffle_core::events::KeyDescriptor {
        physical_key: physical_key_from_str(&logical_key),
        logical_key: logical_key_from_str(&logical_key),
        key_location: ruffle_core::events::KeyLocation::Standard,
    };
    with_players(move |map| {
        let entry = map
            .get(&player_id)
            .ok_or_else(|| anyhow::anyhow!("player not found: {player_id}"))?;
        let mut player_lock = entry.player.lock().unwrap();
        Ok(player_lock.handle_event(PlayerEvent::KeyDown { key }))
    })
}

#[flutter_rust_bridge::frb(sync)]
/// 向 player 注入键盘抬起事件（logical_key 支持单字符或常见键名，如 ArrowLeft/Enter）。
pub fn player_key_up(player_id: u64, logical_key: String) -> anyhow::Result<bool> {
    let key = ruffle_core::events::KeyDescriptor {
        physical_key: physical_key_from_str(&logical_key),
        logical_key: logical_key_from_str(&logical_key),
        key_location: ruffle_core::events::KeyLocation::Standard,
    };
    with_players(move |map| {
        let entry = map
            .get(&player_id)
            .ok_or_else(|| anyhow::anyhow!("player not found: {player_id}"))?;
        let mut player_lock = entry.player.lock().unwrap();
        Ok(player_lock.handle_event(PlayerEvent::KeyUp { key }))
    })
}

#[flutter_rust_bridge::frb(sync)]
/// 向 player 注入文本输入事件（单个 codepoint）。
pub fn player_text_input(player_id: u64, codepoint: String) -> anyhow::Result<bool> {
    let ch = codepoint
        .chars()
        .next()
        .ok_or_else(|| anyhow::anyhow!("empty codepoint"))?;
    with_players(move |map| {
        let entry = map
            .get(&player_id)
            .ok_or_else(|| anyhow::anyhow!("player not found: {player_id}"))?;
        let mut player_lock = entry.player.lock().unwrap();
        Ok(player_lock.handle_event(PlayerEvent::TextInput { codepoint: ch }))
    })
}
