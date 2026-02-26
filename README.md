# Flutter Ruffle

[English](#english) | [中文](#中文)

---

## English

Flutter Ruffle is a cross-platform Flash (SWF) player built with Flutter, powered by the Rust-based [Ruffle](https://github.com/ruffle-rs/ruffle) runtime.

### Features

- Open and play local SWF files.
- Load SWF from HTTP/HTTPS URLs.
- Desktop offscreen rendering with Flutter Texture (PixelBuffer).
- Platform-surface rendering where available (e.g. iOS/macOS/Android).
- Basic safety UX for network behaviors (e.g. confirm before allowing SWF socket connections).

### Supported Platforms

- Android
- iOS
- macOS
- Windows
- Linux

Web is not supported.

### How It Works (High-Level)

This project wraps the Ruffle engine into a Flutter app via an FFI plugin:

- **Flutter UI (Dart)**: file/URL selection, player controls, HUD, virtual input overlays.
- **Background isolate**: runs a worker that communicates with the native side and keeps the UI responsive.
- **FFI bridge**: implemented with `flutter_rust_bridge` in the `ruffle` plugin package.
- **Rendering paths**:
  - **Platform surface mode** (iOS/macOS/Android): the native side renders into a platform surface (e.g. CoreAnimation layer or ANativeWindow).
  - **Offscreen mode** (Windows/Linux): the native side renders RGBA frames; Flutter displays them using a desktop texture (PixelBuffer) and signals frame availability via the texture registrar.

### Build & Run

Prerequisites:

- Flutter is managed via FVM. Use `fvm flutter` instead of `flutter`.
- Git submodules are used for third-party sources.
- Rust toolchain: `packages/ruffle` uses a pinned nightly toolchain (see `packages/ruffle/rust/rust-toolchain.toml`).
- Ruffle is pinned by git submodule commit (not automatically tracking upstream). Update intentionally by changing the submodule commit in this repository.

Commands:

```bash
git submodule update --init --recursive
fvm flutter pub get
fvm flutter run
```

Release builds:

```bash
fvm flutter build apk --release
fvm flutter build windows --release
fvm flutter build macos --release
fvm flutter build ios --release
fvm flutter build linux --release
```

### Repository Layout

- `lib/`: Flutter app UI and player logic.
- `packages/ruffle/`: Flutter FFI plugin bridging Dart ↔ Rust (and desktop texture code).
- `packages/ruffle/third_party/ruffle/`: Ruffle upstream (git submodule).

### License & Disclaimer

This repository integrates upstream projects (e.g. Ruffle). Licensing follows their respective licenses. Please review upstream licenses before redistribution.

---

## 中文

Flutter Ruffle 是一个基于 Flutter 的跨平台 Flash（SWF）播放器，底层运行时由 Rust 实现的 [Ruffle](https://github.com/ruffle-rs/ruffle) 提供。

### 功能特性

- 打开并播放本地 SWF 文件。
- 支持通过 HTTP/HTTPS 链接加载 SWF。
- 桌面端使用 Flutter Texture（PixelBuffer）进行离屏渲染显示。
- 在支持的平台上走原生 Surface 渲染（例如 iOS/macOS/Android）。
- 对部分网络行为提供基础安全交互（例如 SWF 发起 Socket 连接前弹窗确认）。

### 支持平台

- Android
- iOS
- macOS
- Windows
- Linux

不支持 Web 平台。

### 技术原理（概览）

本项目将 Ruffle 引擎通过 FFI 插件接入 Flutter 应用：

- **Flutter UI（Dart）**：文件/链接选择、播放器控制、HUD、虚拟键盘/手柄等。
- **后台 Isolate**：通过 worker 在后台处理与原生侧的通信，避免阻塞 UI。
- **FFI 桥接**：`packages/ruffle` 使用 `flutter_rust_bridge` 实现 Dart ↔ Rust 调用。
- **两条渲染链路**：
  - **平台 Surface 模式**（iOS/macOS/Android）：原生侧直接渲染到平台提供的 Surface（如 CoreAnimation Layer、ANativeWindow）。
  - **离屏模式**（Windows/Linux）：原生侧输出 RGBA 帧，Flutter 侧用桌面 Texture（PixelBuffer）展示，并通过 TextureRegistrar 通知新帧可用。

### 构建与运行

前置要求：

- Flutter 通过 FVM 管理，请使用 `fvm flutter`。
- 三方源码使用 Git submodule 管理。
- Rust 工具链：`packages/ruffle` 使用固定版本的 nightly（见 `packages/ruffle/rust/rust-toolchain.toml`）。
- Ruffle 通过 git submodule 的 commit 固定（不会自动跟随上游变化），需要手动更新本仓库记录的 submodule commit 才会升级。

常用命令：

```bash
git submodule update --init --recursive
fvm flutter pub get
fvm flutter run
```

打包命令（示例）：

```bash
fvm flutter build apk --release
fvm flutter build windows --release
fvm flutter build macos --release
fvm flutter build ios --release
fvm flutter build linux --release
```

### 目录结构

- `lib/`：Flutter 应用 UI 与播放逻辑。
- `packages/ruffle/`：Flutter FFI 插件（Dart ↔ Rust）以及桌面纹理相关代码。
- `packages/ruffle/third_party/ruffle/`：Ruffle 上游仓库（git submodule）。

### 许可与声明

本仓库集成了上游项目（例如 Ruffle）。具体许可协议以各上游仓库为准，分发/商用前请自行确认并遵循对应许可。
