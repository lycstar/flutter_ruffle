import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:math' as math;

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:ruffle/ruffle.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models/swf_info.dart';
import '../widgets/virtual_gamepad.dart';
import '../widgets/virtual_keyboard.dart';
import '../worker/ruffle_worker.dart';
import 'player_hud.dart';
import 'player_input_region.dart';
import 'player_menu_button.dart';
import 'player_surface_view.dart';

class PlayerPage extends StatefulWidget {
  final SwfSource source;

  const PlayerPage({super.key, required this.source});

  @override
  /// 创建播放器页状态对象。
  State<PlayerPage> createState() => _PlayerPageState();
}

class _PlayerPageState extends State<PlayerPage> with WidgetsBindingObserver {
  final RuffleWorker _worker = RuffleWorker();
  final FocusNode _focusNode = FocusNode();
  final List<String> _pendingExternalUrls = <String>[];
  bool _externalUrlDialogShowing = false;
  final List<_PendingSocketRequest> _pendingSocketRequests =
      <_PendingSocketRequest>[];
  bool _socketDialogShowing = false;

  final Set<String> _pressedPhysicalLogicalKeys = <String>{};
  final Set<String> _pressedVirtualLogicalKeys = <String>{};
  SwfInfo? _swfInfo;
  int? _surfaceViewId;
  int? _surfaceLayerPtr;
  bool _surfacePlayerCreating = false;
  bool _offscreenPlayerCreating = false;
  bool _offscreenDecodeInFlight = false;
  int? _desktopTextureId;
  bool _desktopTextureCreating = false;
  bool _workerReady = false;
  String? _storageBaseDirPath;
  VirtualGamepadConfigStore _gamepadStore = VirtualGamepadConfigStore.defaults();

  final Stopwatch _pumpClock = Stopwatch();
  Timer? _pumpTimer;
  Duration _lastPumpElapsed = Duration.zero;
  bool _pumpInFlight = false;
  bool _appIsActive = true;
  int? _lastInvalidSurfaceRecoverMicros;

  final List<int> _recentPumpFrameTimesMicros = <int>[];
  final List<int> _recentPresentedFrameTimesMicros = <int>[];
  int? _lastHudUpdateMicros;
  int? _lastViewportWidthPx;
  int? _lastViewportHeightPx;
  double? _lastViewportScaleFactor;
  bool _viewportUpdateInFlight = false;
  int? _lastMissingPlayerRecoverMicros;

  bool _showVirtualKeyboard = false;
  bool _showVirtualGamepad = false;

  bool _useSurface() =>
      Platform.isMacOS || Platform.isIOS || Platform.isAndroid;

  /// 获取虚拟手柄配置文件路径（位于 ApplicationSupport）。
  String? _gamepadConfigFilePath() {
    final base = _storageBaseDirPath;
    if (base == null || base.isEmpty) return null;
    return '$base/gamepad_config.json';
  }

  /// 读取本地虚拟手柄配置集合（不存在/解析失败则保持默认）。
  Future<void> _loadGamepadConfig() async {
    final path = _gamepadConfigFilePath();
    if (path == null) return;
    try {
      final file = File(path);
      if (await file.exists()) {
        final raw = await file.readAsString();
        final decoded = jsonDecode(raw);
        if (decoded is! Map) return;
        _gamepadStore = VirtualGamepadConfigStore.fromJson(
          Map<String, Object?>.from(decoded),
        );
      }
    } catch (_) {}
  }

  /// 写入本地虚拟手柄配置集合（失败则静默忽略）。
  Future<void> _saveGamepadConfig() async {
    final path = _gamepadConfigFilePath();
    if (path == null) return;
    try {
      final file = File(path);
      await file.writeAsString(jsonEncode(_gamepadStore.toJson()));
    } catch (_) {}
  }

  /// 虚拟手柄请求改键：提供常用候选 + 支持手动输入。
  Future<String?> _pickGamepadLogicalKey({
    required BuildContext context,
    required String controlId,
    required String current,
  }) async {
    String? joystickId;
    String? joystickDir;
    if (controlId.startsWith('joystick:')) {
      final parts = controlId.split(':');
      if (parts.length == 2) {
        joystickDir = parts[1];
      } else if (parts.length >= 3) {
        joystickId = parts[1];
        joystickDir = parts[2];
      }
    }

    final suggestions = switch (joystickDir) {
      'up' => const ['ArrowUp', 'w', 'i'],
      'down' => const ['ArrowDown', 's', 'k'],
      'left' => const ['ArrowLeft', 'a', 'j'],
      'right' => const ['ArrowRight', 'd', 'l'],
      _ => const ['z', 'x', 'c', ' ', 'Enter', 'Escape'],
    };
    final dirTitle = switch (joystickDir) {
      'up' => '上',
      'down' => '下',
      'left' => '左',
      'right' => '右',
      _ => null,
    };
    final title = dirTitle == null
        ? '按键映射'
        : joystickId == null
            ? '摇杆：$dirTitle'
            : '摇杆($joystickId)：$dirTitle';
    final next = await _pickLogicalKey(
      context: context,
      title: title,
      current: current,
      suggestions: suggestions,
    );
    if (next == null) return null;
    final normalized = _normalizeLogicalKeyInput(next);
    return normalized.isEmpty ? null : normalized;
  }

  /// 虚拟手柄保存配置集合：写入本地并刷新 UI（同时释放当前虚拟按键按住状态）。
  Future<void> _saveGamepadStoreFromWidget(VirtualGamepadConfigStore store) async {
    unawaited(_releaseVirtualPressedKeys());
    if (!mounted) return;
    setState(() {
      _gamepadStore = store;
    });
    await _saveGamepadConfig();
  }

  /// 标准化用户输入的 logicalKey：字母统一为小写；空格接受 space/␠；方向键/Enter/Escape 允许大小写。
  String _normalizeLogicalKeyInput(String raw) {
    final s = raw.trim();
    if (s.isEmpty) return s;
    final lower = s.toLowerCase();
    if (lower == 'space' || s == '␠') return ' ';
    if (lower == 'enter') return 'Enter';
    if (lower == 'esc' || lower == 'escape') return 'Escape';
    if (lower == 'arrowup') return 'ArrowUp';
    if (lower == 'arrowdown') return 'ArrowDown';
    if (lower == 'arrowleft') return 'ArrowLeft';
    if (lower == 'arrowright') return 'ArrowRight';
    if (s.length == 1) return s.toLowerCase();
    return s;
  }

  /// 选择一个 logicalKey：提供常用候选 + 支持手动输入。
  Future<String?> _pickLogicalKey({
    required BuildContext context,
    required String title,
    required String current,
    required List<String> suggestions,
  }) async {
    final controller = TextEditingController(
      text: current == ' ' ? 'space' : current,
    );
    final result = await showCupertinoDialog<String>(
      context: context,
      builder: (context) {
        Widget suggestionChip(String s) {
          return SizedBox(
            height: 28,
            child: CupertinoButton(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              color: CupertinoColors.systemGrey5,
              borderRadius: BorderRadius.circular(999),
              onPressed: () => Navigator.of(context).pop(s),
              child: Text(
                s == ' ' ? 'space' : s,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: CupertinoColors.label,
                ),
              ),
            ),
          );
        }

        return CupertinoAlertDialog(
          title: Text(title),
          content: Padding(
            padding: const EdgeInsets.only(top: 10),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  CupertinoTextField(
                    controller: controller,
                    placeholder: 'logicalKey',
                    autofocus: true,
                    textInputAction: TextInputAction.done,
                    onSubmitted: (v) => Navigator.of(context).pop(v),
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [for (final s in suggestions) suggestionChip(s)],
                  ),
                ],
              ),
            ),
          ),
          actions: [
            CupertinoDialogAction(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('取消'),
            ),
            CupertinoDialogAction(
              onPressed: () => Navigator.of(context).pop(controller.text),
              isDefaultAction: true,
              child: const Text('确定'),
            ),
          ],
        );
      },
    );
    controller.dispose();
    return result;
  }

  @override
  /// 初始化页面：启动 worker，等待平台 Surface 就绪后创建 player。
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    unawaited(_initWorker());
  }

  @override
  /// 释放资源：停止主循环、销毁平台视图关联资源、关闭 worker。
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _stopPumpLoop();
    _pumpClock.stop();
    unawaited(_releaseAllPressedKeys());
    _focusNode.dispose();
    final textureId = _desktopTextureId;
    if (textureId != null) {
      unawaited(RuffleTexture.disposeTexture(textureId: textureId));
    }
    final surfaceViewId = _surfaceViewId;
    if (surfaceViewId != null) {
      unawaited(RuffleSurface.disposeView(viewId: surfaceViewId));
    }
    _workerReady = false;
    unawaited(_worker.shutdown());
    super.dispose();
  }

  /// 仅初始化 worker（player 创建由 Surface ready + viewport 确定后触发）。
  Future<void> _initWorker() async {
    try {
      final baseDir = await getApplicationSupportDirectory();
      _storageBaseDirPath = baseDir.path;
      await _loadGamepadConfig();
      await _worker.start(storageBaseDir: baseDir.path);
      _workerReady = true;
      if (!mounted) return;
      setState(() {});
    } catch (e) {
      if (!mounted) return;
      await _showErrorDialog('加载失败', e.toString());
      if (mounted) {
        Navigator.of(context).pop();
      }
    }
  }

  /// 串行处理外部链接打开请求：弹窗确认后再通过系统浏览器打开。
  Future<void> _processExternalUrlQueue() async {
    if (!mounted) return;
    if (_externalUrlDialogShowing) return;
    if (_pendingExternalUrls.isEmpty) return;
    _externalUrlDialogShowing = true;
    try {
      final url = _pendingExternalUrls.removeAt(0);
      final shouldOpen = await _showConfirmOpenUrlDialog(url);
      if (shouldOpen != true) return;
      final uri = Uri.tryParse(url);
      if (uri == null) {
        await _showErrorDialog('无法打开链接', 'URL 格式不正确：$url');
        return;
      }
      final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (!ok) {
        await _showErrorDialog('无法打开链接', '系统未能打开：$url');
      }
    } finally {
      _externalUrlDialogShowing = false;
      if (_pendingExternalUrls.isNotEmpty) {
        unawaited(_processExternalUrlQueue());
      }
    }
  }

  /// 弹窗确认是否打开外部链接。
  Future<bool?> _showConfirmOpenUrlDialog(String url) async {
    if (!mounted) return false;
    return showCupertinoDialog<bool>(
      context: context,
      builder: (context) {
        return CupertinoAlertDialog(
          title: const Text('打开外部链接'),
          content: Padding(
            padding: const EdgeInsets.only(top: 10),
            child: SelectableText('SWF 请求打开以下链接：\n\n$url'),
          ),
          actions: [
            CupertinoDialogAction(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('取消'),
            ),
            CupertinoDialogAction(
              onPressed: () => Navigator.of(context).pop(true),
              isDefaultAction: true,
              child: const Text('打开'),
            ),
          ],
        );
      },
    );
  }

  /// 串行处理 Socket 连接确认请求：弹窗确认后再放行/拒绝（对齐桌面端 SocketMode::Ask 行为）。
  Future<void> _processSocketRequestQueue() async {
    if (!mounted) return;
    if (_socketDialogShowing) return;
    if (_pendingSocketRequests.isEmpty) return;
    _socketDialogShowing = true;
    try {
      final req = _pendingSocketRequests.removeAt(0);
      final shouldAllow = await _showConfirmSocketConnectDialog(
        host: req.host,
        port: req.port,
      );
      navigatorResolvePendingSocketRequest(
        requestId: req.requestId,
        allow: shouldAllow == true,
      );
    } finally {
      _socketDialogShowing = false;
      if (_pendingSocketRequests.isNotEmpty) {
        unawaited(_processSocketRequestQueue());
      }
    }
  }

  /// 弹窗确认是否允许 SWF 发起 Socket 连接。
  Future<bool?> _showConfirmSocketConnectDialog({
    required String host,
    required int port,
  }) async {
    if (!mounted) return false;
    return showCupertinoDialog<bool>(
      context: context,
      builder: (context) {
        return CupertinoAlertDialog(
          title: const Text('Socket 连接请求'),
          content: Padding(
            padding: const EdgeInsets.only(top: 10),
            child: SelectableText('SWF 请求建立 Socket 连接：\n\n$host:$port'),
          ),
          actions: [
            CupertinoDialogAction(
              onPressed: () => Navigator.of(context).pop(false),
              isDestructiveAction: true,
              child: const Text('拒绝'),
            ),
            CupertinoDialogAction(
              onPressed: () => Navigator.of(context).pop(true),
              isDefaultAction: true,
              child: const Text('允许'),
            ),
          ],
        );
      },
    );
  }

  /// 启动持续刷新循环：按 ruffle 的 time_til_next_frame 节奏驱动 tick+present（对齐 ruffle-android 的事件循环策略）。
  void _startPumpLoopIfNeeded() {
    if (_pumpTimer != null) return;
    if (!_pumpClock.isRunning) {
      _pumpClock.start();
    }
    _lastPumpElapsed = Duration.zero;
    _scheduleNextPump(const Duration(milliseconds: 0));
  }

  /// 停止持续刷新循环。
  void _stopPumpLoop() {
    _pumpTimer?.cancel();
    _pumpTimer = null;
    _lastPumpElapsed = Duration.zero;
    _pumpInFlight = false;
  }

  /// 安排下一次 pump。
  void _scheduleNextPump(Duration delay) {
    _pumpTimer?.cancel();
    _pumpTimer = Timer(delay, () {
      if (!mounted) return;
      if (!_appIsActive) return;
      if (!_workerReady) return;
      if (_swfInfo == null) return;
      if (_pumpInFlight) return;
      unawaited(_pumpOnce(nowElapsed: _pumpClock.elapsed));
    });
  }

  /// 请求尽快执行一次 pump（不等待下一次定时触发）。
  void _requestPumpSoon() {
    if (!_appIsActive) return;
    if (!_workerReady) return;
    if (_swfInfo == null) return;
    _startPumpLoopIfNeeded();
    _scheduleNextPump(const Duration(milliseconds: 0));
  }

  /// 执行一次 tick + render present（Surface 直出）。
  Future<void> _pumpOnce({required Duration nowElapsed}) async {
    if (!_appIsActive) return;
    if (!_workerReady) return;
    if (_swfInfo == null) return;
    if (_pumpInFlight) return;

    _pumpInFlight = true;
    final stopwatch = Stopwatch()..start();
    try {
      if (_viewportUpdateInFlight) {
        _scheduleNextPump(const Duration(milliseconds: 0));
        return;
      }
      final hadPrev = _lastPumpElapsed != Duration.zero;
      final dt = hadPrev ? (nowElapsed - _lastPumpElapsed) : Duration.zero;
      _lastPumpElapsed = nowElapsed;
      if (hadPrev) {
        _recordPumpFrame(nowElapsed);
      }
      final dtMillis = (dt.inMicroseconds / 1000.0).clamp(0.0, 100.0);
      final result = _useSurface()
          ? await _worker.tickAndRenderSurface(dtMillis: dtMillis)
          : await _pumpOffscreen(dtMillis: dtMillis);
      final externalUrls = result['externalUrls'];
      if (externalUrls is List) {
        for (final item in externalUrls) {
          if (item is String && item.isNotEmpty) {
            _pendingExternalUrls.add(item);
          }
        }
        if (_pendingExternalUrls.isNotEmpty) {
          unawaited(_processExternalUrlQueue());
        }
      }

      final socketRequests = result['socketRequests'];
      if (socketRequests is List) {
        for (final item in socketRequests) {
          if (item is! Map) continue;
          final requestId = item['requestId'];
          final host = item['host'];
          final port = item['port'];
          if (requestId is! BigInt || host is! String || port is! int) continue;
          _pendingSocketRequests.add(
            _PendingSocketRequest(requestId: requestId, host: host, port: port),
          );
        }
        if (_pendingSocketRequests.isNotEmpty) {
          unawaited(_processSocketRequestQueue());
        }
      }
      if (hadPrev) {
        final hasFrame = result['hasFrame'];
        if (hasFrame is bool && hasFrame) {
          _recordPresentedFrame(nowElapsed);
        }
      }
      final timeTilNextFrameMillis = result['timeTilNextFrameMillis'];
      final waitMs =
          (timeTilNextFrameMillis is num ? timeTilNextFrameMillis.toInt() : 16)
              .clamp(0, 100);
      _scheduleNextPump(Duration(milliseconds: waitMs));
    } catch (e) {
      _stopPumpLoop();
      final err = e.toString();
      if (err.contains('player not found:')) {
        final recovered = await _recoverFromMissingPlayer(
          nowMicros: nowElapsed.inMicroseconds,
        );
        if (recovered) return;
      }
      if (Platform.isAndroid && err.contains('Invalid surface')) {
        await _recoverFromInvalidSurface(nowMicros: nowElapsed.inMicroseconds);
        return;
      }
      _appIsActive = false;
      await _showErrorDialog('渲染失败', e.toString());
    } finally {
      stopwatch.stop();
      _pumpInFlight = false;
    }
  }

  /// 平台 Surface 渲染路径：当 wgpu 报 `Invalid surface` 时尝试自动恢复。
  /// 当 wgpu 报 `Invalid surface` 时尝试自动恢复：
  /// - 重新拉取最新的 ANativeWindow 指针
  /// - 若指针变化则触发 Rust 侧重建 surface
  /// - 恢复主循环继续渲染
  Future<void> _recoverFromInvalidSurface({required int nowMicros}) async {
    const minIntervalMicros = 1_000_000;
    final last = _lastInvalidSurfaceRecoverMicros;
    if (last != null && nowMicros - last < minIntervalMicros) {
      return;
    }
    _lastInvalidSurfaceRecoverMicros = nowMicros;

    _stopPumpLoop();
    await _refreshSurfacePtrAfterResume();
    if (!_appIsActive) return;
    _startPumpLoopIfNeeded();
    _requestPumpSoon();
  }

  /// 选择 viewport 的渲染倍率：在 Android 上对总像素量做上限约束，避免高 DPR/大屏导致掉帧。
  double _chooseViewportScaleFactor({
    required double devicePixelRatio,
    required double maxW,
    required double maxH,
  }) {
    if (!devicePixelRatio.isFinite || devicePixelRatio <= 0) return 1.0;
    if (!maxW.isFinite || !maxH.isFinite || maxW <= 0 || maxH <= 0) {
      return devicePixelRatio;
    }

    if (!Platform.isAndroid) return devicePixelRatio;

    const maxRenderPixels = 2_073_600.0;
    final desiredPixels = maxW * maxH * devicePixelRatio * devicePixelRatio;
    if (!desiredPixels.isFinite || desiredPixels <= 0) return devicePixelRatio;

    var scale = devicePixelRatio;
    if (desiredPixels > maxRenderPixels) {
      final shrink = math.sqrt(maxRenderPixels / desiredPixels);
      scale = devicePixelRatio * shrink;
    }

    scale = (scale * 8.0).roundToDouble() / 8.0;
    return scale.clamp(0.5, devicePixelRatio);
  }

  /// 离屏渲染路径：tick 后如需渲染则抓取 RGBA，并通过平台 PixelBufferTexture 通知 Flutter 刷新。
  Future<Map<String, Object?>> _pumpOffscreen({
    required double dtMillis,
  }) async {
    if (_offscreenDecodeInFlight) {
      await _worker.tickOnly(dtMillis: dtMillis);
      return const {
        'hasFrame': false,
        'timeTilNextFrameMillis': 16,
        'externalUrls': <String>[],
      };
    }

    final result = await _worker.tickAndRenderOffscreen(dtMillis: dtMillis);
    final hasFrame = result['hasFrame'];
    if (hasFrame is! bool || !hasFrame) return result;

    final ttd = result['rgba'];
    final width = result['width'];
    final height = result['height'];
    if (ttd is! TransferableTypedData || width is! int || height is! int) {
      return result;
    }

    _offscreenDecodeInFlight = true;
    try {
      await _ensureDesktopTextureReady();
      final textureId = _desktopTextureId;
      if (textureId == null) return result;
      final rgba = ttd.materialize().asUint8List();
      await RuffleTexture.updateRgba(
        textureId: textureId,
        rgba: rgba,
        width: width,
        height: height,
      );
    } finally {
      _offscreenDecodeInFlight = false;
    }
    return result;
  }

  /// 确保桌面端 PixelBufferTexture 已创建，并在首次创建后触发一次重建以展示 `Texture` 组件。
  Future<void> _ensureDesktopTextureReady() async {
    if (_desktopTextureId != null) return;
    if (_desktopTextureCreating) return;
    _desktopTextureCreating = true;
    try {
      final id = await RuffleTexture.create();
      _desktopTextureId = id;
      if (mounted) {
        setState(() {});
      }
    } finally {
      _desktopTextureCreating = false;
    }
  }

  /// 记录主循环帧时间戳（用于计算“主循环帧率”，不依赖 needsRender）。
  void _recordPumpFrame(Duration nowElapsed) {
    final nowMicros = nowElapsed.inMicroseconds;
    _recentPumpFrameTimesMicros.add(nowMicros);
    const windowMicros = 1_500_000;
    final cutoff = nowMicros - windowMicros;
    while (_recentPumpFrameTimesMicros.length > 2 &&
        _recentPumpFrameTimesMicros.first < cutoff) {
      _recentPumpFrameTimesMicros.removeAt(0);
    }
    _maybeUpdateHud(nowMicros);
  }

  /// 记录已 present 的帧时间戳（用于计算实际渲染 FPS，与桌面端“只在 needs_render 时 request_redraw”口径一致）。
  void _recordPresentedFrame(Duration nowElapsed) {
    final nowMicros = nowElapsed.inMicroseconds;
    _recentPresentedFrameTimesMicros.add(nowMicros);
    const windowMicros = 1_500_000;
    final cutoff = nowMicros - windowMicros;
    while (_recentPresentedFrameTimesMicros.length > 2 &&
        _recentPresentedFrameTimesMicros.first < cutoff) {
      _recentPresentedFrameTimesMicros.removeAt(0);
    }
    _maybeUpdateHud(nowMicros);
  }

  /// 低频刷新 HUD（避免每一帧 setState）。
  void _maybeUpdateHud(int nowMicros) {
    const minIntervalMicros = 250000;
    final last = _lastHudUpdateMicros;
    if (last != null && nowMicros - last < minIntervalMicros) return;
    _lastHudUpdateMicros = nowMicros;
    if (!mounted) return;
    setState(() {});
  }

  @override
  /// 处理应用生命周期变化：对齐 FocusGained/FocusLost，并在恢复时强制拉一帧。
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _appIsActive = true;
      unawaited(_refreshSurfacePtrAfterResume());
      if (_workerReady) {
        _fire(_worker.sendFocusGained);
        _fire(() => _worker.setIsPlaying(isPlaying: true));
      }
      if (mounted) {
        setState(() {});
      }
      _requestPumpSoon();
      return;
    }
    if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached) {
      _appIsActive = false;
      _stopPumpLoop();
      unawaited(_releaseAllPressedKeys());
      if (mounted) {
        setState(() {
          _surfaceLayerPtr = null;
        });
      } else {
        _surfaceLayerPtr = null;
      }
      if (_workerReady) {
        _fire(_worker.sendFocusLost);
        _fire(() => _worker.setIsPlaying(isPlaying: false));
      }
    }
  }

  /// 应用恢复后重新获取平台 Surface 指针，避免后台切换导致的 Surface 失效/指针变化。
  Future<void> _refreshSurfacePtrAfterResume() async {
    if (!_useSurface()) return;
    if (!_workerReady) return;
    final viewId = _surfaceViewId;
    if (viewId == null) return;
    try {
      const maxAttempts = 120;
      for (var attempt = 0; attempt < maxAttempts; attempt++) {
        final ptr = await RuffleSurface.getLayerPtr(viewId: viewId);
        if (ptr != 0) {
          final oldPtr = _surfaceLayerPtr;
          final currentWidth = _lastViewportWidthPx;
          final currentHeight = _lastViewportHeightPx;
          final currentScale = _lastViewportScaleFactor;
          if (!mounted) {
            _surfaceLayerPtr = ptr;
            if (oldPtr != ptr &&
                _swfInfo != null &&
                currentWidth != null &&
                currentHeight != null &&
                currentScale != null) {
              unawaited(
                _worker.recreateSurfacePlatform(
                  surfacePtr: ptr,
                  width: currentWidth,
                  height: currentHeight,
                  scaleFactor: currentScale,
                ),
              );
            }
            return;
          }
          if (oldPtr != ptr) {
            setState(() {
              _surfaceLayerPtr = ptr;
            });
            if (_swfInfo != null &&
                currentWidth != null &&
                currentHeight != null &&
                currentScale != null) {
              unawaited(
                _worker.recreateSurfacePlatform(
                  surfacePtr: ptr,
                  width: currentWidth,
                  height: currentHeight,
                  scaleFactor: currentScale,
                ),
              );
            }
          }
          return;
        }
        await Future<void>.delayed(const Duration(milliseconds: 16));
      }
    } catch (_) {}
  }

  /// 显示错误弹窗。
  Future<void> _showErrorDialog(String title, String message) async {
    if (!mounted) return;
    await showCupertinoDialog<void>(
      context: context,
      builder: (context) {
        return CupertinoAlertDialog(
          title: Text(title),
          content: Padding(
            padding: const EdgeInsets.only(top: 10),
            child: Text(message),
          ),
          actions: [
            CupertinoDialogAction(
              onPressed: () => Navigator.of(context).pop(),
              isDefaultAction: true,
              child: const Text('确定'),
            ),
          ],
        );
      },
    );
  }

  /// 根据当前布局尺寸更新 player 的 viewport；若尚未创建 player，则在 Surface 就绪后创建。
  void _updateViewportIfNeeded({
    required double maxW,
    required double maxH,
    required double scaleFactor,
  }) {
    final widthPx = (maxW * scaleFactor).round().clamp(1, 1 << 30);
    final heightPx = (maxH * scaleFactor).round().clamp(1, 1 << 30);
    if (!_workerReady) return;
    if (!_appIsActive) return;
    final useSurface = _useSurface();
    final layerPtr = _surfaceLayerPtr;
    if (useSurface && layerPtr == null) return;
    if (_viewportUpdateInFlight) return;
    if (_swfInfo != null) {
      final lastW = _lastViewportWidthPx;
      final lastH = _lastViewportHeightPx;
      final lastScale = _lastViewportScaleFactor;
      if (lastW != null && lastH != null && lastScale != null) {
        final sameSize =
            (lastW - widthPx).abs() <= 1 && (lastH - heightPx).abs() <= 1;
        final sameScale = (lastScale - scaleFactor).abs() < 0.001;
        if (sameSize && sameScale) return;
      }
    }

    _viewportUpdateInFlight = true;
    _lastViewportWidthPx = widthPx;
    _lastViewportHeightPx = heightPx;
    _lastViewportScaleFactor = scaleFactor;

    unawaited(() async {
      try {
        final useSurface = _useSurface();
        if (useSurface && Platform.isAndroid) {
          await _refreshSurfacePtrForAndroidViewport();
        }

        if (_swfInfo == null &&
            !_surfacePlayerCreating &&
            !_offscreenPlayerCreating) {
          late final Map<String, Object?> created;
          if (useSurface) {
            final surfacePtr = _surfaceLayerPtr;
            if (surfacePtr == null) return;
            _surfacePlayerCreating = true;
            created = await _worker.createFromBytesPlatformSurface(
              bytes: widget.source.bytes,
              url: widget.source.url,
              name: widget.source.name,
              surfacePtr: surfacePtr,
              width: widthPx,
              height: heightPx,
              scaleFactor: scaleFactor,
            );
          } else {
            _offscreenPlayerCreating = true;
            created = await _worker.createFromBytesOffscreen(
              bytes: widget.source.bytes,
              url: widget.source.url,
              name: widget.source.name,
              width: widthPx,
              height: heightPx,
              scaleFactor: scaleFactor,
            );
          }
          final headerMap = created['header'] as Map<Object?, Object?>?;
          if (headerMap == null) {
            throw StateError('worker 返回数据缺失');
          }
          final header = SwfHeaderInfo(
            swfVersion: (headerMap['swfVersion'] as int),
            widthPx: (headerMap['widthPx'] as num).toDouble(),
            heightPx: (headerMap['heightPx'] as num).toDouble(),
            frameRate: (headerMap['frameRate'] as num).toDouble(),
            numFrames: (headerMap['numFrames'] as int),
            compression: (headerMap['compression'] as String),
            isActionScript3: (headerMap['isActionScript3'] as bool),
          );
          final swfInfo = SwfInfo(source: widget.source, header: header);
          if (!mounted) return;
          setState(() {
            _swfInfo = swfInfo;
          });
          _startPumpLoopIfNeeded();
        }
        if (_swfInfo == null) return;
        await _worker.setViewportDimensions(
          width: widthPx,
          height: heightPx,
          scaleFactor: scaleFactor,
        );
      } catch (e) {
        final err = e.toString();
        if (err.contains('player not found:')) {
          final recovered = await _recoverFromMissingPlayer(
            nowMicros: DateTime.now().microsecondsSinceEpoch,
          );
          if (recovered) return;
        }
        if (mounted) {
          await _showErrorDialog('初始化失败', e.toString());
          if (mounted) {
            Navigator.of(context).pop();
          }
        }
      } finally {
        _surfacePlayerCreating = false;
        _offscreenPlayerCreating = false;
        _viewportUpdateInFlight = false;
        _requestPumpSoon();
      }
    }());
  }

  /// 当 Rust 侧丢失 player（常见于后台挂起/重建导致 worker/全局状态被清空）时，尝试自动重建并继续播放。
  Future<bool> _recoverFromMissingPlayer({required int nowMicros}) async {
    const minIntervalMicros = 1_000_000;
    final last = _lastMissingPlayerRecoverMicros;
    if (last != null && nowMicros - last < minIntervalMicros) {
      return false;
    }
    _lastMissingPlayerRecoverMicros = nowMicros;

    _stopPumpLoop();
    unawaited(_releaseAllPressedKeys());
    try {
      await _worker.disposePlayer().catchError((_) {});
    } catch (_) {}

    final widthPx = _lastViewportWidthPx;
    final heightPx = _lastViewportHeightPx;
    final scaleFactor = _lastViewportScaleFactor;
    if (widthPx == null || heightPx == null || scaleFactor == null) {
      return false;
    }

    if (mounted) {
      setState(() {
        _swfInfo = null;
      });
    } else {
      _swfInfo = null;
    }

    try {
      final useSurface = _useSurface();
      if (useSurface) {
        await _refreshSurfacePtrAfterResume();
        final surfacePtr = _surfaceLayerPtr;
        if (surfacePtr == null) return false;
        final created = await _worker.createFromBytesPlatformSurface(
          bytes: widget.source.bytes,
          url: widget.source.url,
          name: widget.source.name,
          surfacePtr: surfacePtr,
          width: widthPx,
          height: heightPx,
          scaleFactor: scaleFactor,
        );
        final headerMap = created['header'] as Map<Object?, Object?>?;
        if (headerMap == null) return false;
        final header = SwfHeaderInfo(
          swfVersion: (headerMap['swfVersion'] as int),
          widthPx: (headerMap['widthPx'] as num).toDouble(),
          heightPx: (headerMap['heightPx'] as num).toDouble(),
          frameRate: (headerMap['frameRate'] as num).toDouble(),
          numFrames: (headerMap['numFrames'] as int),
          compression: (headerMap['compression'] as String),
          isActionScript3: (headerMap['isActionScript3'] as bool),
        );
        final swfInfo = SwfInfo(source: widget.source, header: header);
        if (mounted) {
          setState(() {
            _swfInfo = swfInfo;
          });
        } else {
          _swfInfo = swfInfo;
        }
      } else {
        final created = await _worker.createFromBytesOffscreen(
          bytes: widget.source.bytes,
          url: widget.source.url,
          name: widget.source.name,
          width: widthPx,
          height: heightPx,
          scaleFactor: scaleFactor,
        );
        final headerMap = created['header'] as Map<Object?, Object?>?;
        if (headerMap == null) return false;
        final header = SwfHeaderInfo(
          swfVersion: (headerMap['swfVersion'] as int),
          widthPx: (headerMap['widthPx'] as num).toDouble(),
          heightPx: (headerMap['heightPx'] as num).toDouble(),
          frameRate: (headerMap['frameRate'] as num).toDouble(),
          numFrames: (headerMap['numFrames'] as int),
          compression: (headerMap['compression'] as String),
          isActionScript3: (headerMap['isActionScript3'] as bool),
        );
        final swfInfo = SwfInfo(source: widget.source, header: header);
        if (mounted) {
          setState(() {
            _swfInfo = swfInfo;
          });
        } else {
          _swfInfo = swfInfo;
        }
      }
      _startPumpLoopIfNeeded();
      _requestPumpSoon();
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Android 上 Surface 可能在旋转/重建时变化，但 Flutter 侧缓存的指针不一定会及时更新。
  /// 这里在触发 viewport 更新前主动拉取一次最新的 surfacePtr，避免 Rust(wgpu) 配置到旧 surface。
  Future<void> _refreshSurfacePtrForAndroidViewport() async {
    if (!Platform.isAndroid) return;
    if (!_useSurface()) return;
    if (!_workerReady) return;
    final viewId = _surfaceViewId;
    if (viewId == null) return;

    try {
      final ptr = await RuffleSurface.getLayerPtr(viewId: viewId);
      if (ptr == 0) {
        if (!mounted) {
          _surfaceLayerPtr = null;
        } else {
          setState(() {
            _surfaceLayerPtr = null;
          });
        }
        return;
      }

      final oldPtr = _surfaceLayerPtr;
      if (oldPtr == ptr) return;

      if (!mounted) {
        _surfaceLayerPtr = ptr;
      } else {
        setState(() {
          _surfaceLayerPtr = ptr;
        });
      }

      final currentWidth = _lastViewportWidthPx;
      final currentHeight = _lastViewportHeightPx;
      final currentScale = _lastViewportScaleFactor;
      if (_swfInfo != null &&
          currentWidth != null &&
          currentHeight != null &&
          currentScale != null) {
        await _worker
            .recreateSurfacePlatform(
              surfacePtr: ptr,
              width: currentWidth,
              height: currentHeight,
              scaleFactor: currentScale,
            )
            .catchError((_) {});
      }
    } catch (_) {}
  }

  /// 防止 KeyUp 丢失导致“按键卡住”：在失焦/暂停/退出时主动抬起所有已按下的键。
  Future<void> _releaseAllPressedKeys() async {
    if (!_workerReady) {
      _pressedPhysicalLogicalKeys.clear();
      _pressedVirtualLogicalKeys.clear();
      return;
    }
    if (_pressedPhysicalLogicalKeys.isEmpty &&
        _pressedVirtualLogicalKeys.isEmpty) {
      return;
    }
    final keys = <String>{
      ..._pressedPhysicalLogicalKeys,
      ..._pressedVirtualLogicalKeys,
    }.toList(growable: false);
    _pressedPhysicalLogicalKeys.clear();
    _pressedVirtualLogicalKeys.clear();
    for (final k in keys) {
      try {
        await _worker.sendKeyUp(logicalKey: k);
      } catch (_) {}
    }
  }

  /// 虚拟输入切换时释放虚拟按键，避免切换面板导致 KeyUp 丢失。
  Future<void> _releaseVirtualPressedKeys() async {
    if (!_workerReady) {
      _pressedVirtualLogicalKeys.clear();
      return;
    }
    if (_pressedVirtualLogicalKeys.isEmpty) return;
    final keys = _pressedVirtualLogicalKeys.toList(growable: false);
    _pressedVirtualLogicalKeys.clear();
    for (final k in keys) {
      try {
        await _worker.sendKeyUp(logicalKey: k);
      } catch (_) {}
    }
  }

  /// 统一的 worker 调用防护：避免 worker 未就绪时抛错。
  void _fire(Future<void> Function() op) {
    if (!_workerReady) return;
    unawaited(op().catchError((_) {}));
  }

  /// 虚拟按键按下：与物理输入共享“已按下集合”，避免重复 KeyDown。
  Future<void> _sendVirtualKeyDown(String logicalKey) async {
    if (!_workerReady) return;
    _focusNode.requestFocus();
    if (_pressedVirtualLogicalKeys.add(logicalKey)) {
      await _worker.sendKeyDown(logicalKey: logicalKey);
      _requestPumpSoon();
    }
  }

  /// 虚拟按键抬起：与物理输入共享“已按下集合”，保证 KeyUp 成对出现。
  Future<void> _sendVirtualKeyUp(String logicalKey) async {
    if (!_workerReady) return;
    _focusNode.requestFocus();
    _pressedVirtualLogicalKeys.remove(logicalKey);
    await _worker.sendKeyUp(logicalKey: logicalKey);
    _requestPumpSoon();
  }

  /// 切换虚拟键盘显示状态（显示键盘时自动隐藏手柄）。
  void _toggleVirtualKeyboard() {
    unawaited(_releaseVirtualPressedKeys());
    setState(() {
      _showVirtualKeyboard = !_showVirtualKeyboard;
      if (_showVirtualKeyboard) {
        _showVirtualGamepad = false;
      }
    });
    _focusNode.requestFocus();
  }

  /// 切换虚拟手柄显示状态（显示手柄时自动隐藏键盘）。
  void _toggleVirtualGamepad() {
    unawaited(_releaseVirtualPressedKeys());
    setState(() {
      _showVirtualGamepad = !_showVirtualGamepad;
      if (_showVirtualGamepad) {
        _showVirtualKeyboard = false;
      }
    });
    _focusNode.requestFocus();
  }

  /// 平台 Surface 就绪回调：记录 viewId/ptr 并请求尽快创建 player。
  void _onSurfaceReady(PlayerSurfaceReady ready) {
    if (!mounted) return;
    setState(() {
      _surfaceViewId = ready.viewId;
      _surfaceLayerPtr = ready.surfacePtr;
    });
    _requestPumpSoon();
  }

  /// 重新加载当前 SWF：释放 player 并重新触发创建流程。
  Future<void> _reload() async {
    unawaited(_releaseAllPressedKeys());
    if (_workerReady) {
      try {
        await _worker.disposePlayer();
      } catch (_) {}
    }
    if (!mounted) return;
    setState(() {
      _swfInfo = null;
      _surfacePlayerCreating = false;
    });
    _requestPumpSoon();
  }

  /// 选择并设置画质（low/medium/high/best...）。
  Future<void> _pickQuality() async {
    if (!_workerReady || _swfInfo == null) return;
    String? current;
    try {
      current = await _worker.getQuality();
    } catch (_) {}
    if (!mounted) return;
    const options = <String>['low', 'medium', 'high', 'best'];
    final selected = await showCupertinoModalPopup<String>(
      context: context,
      builder: (context) {
        return CupertinoActionSheet(
          title: const Text('画质'),
          actions: [
            for (final o in options)
              CupertinoActionSheetAction(
                onPressed: () => Navigator.of(context).pop(o),
                child: Text(
                  o == current ? '✓ ${_qualityLabel(o)}' : _qualityLabel(o),
                ),
              ),
          ],
          cancelButton: CupertinoActionSheetAction(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('取消'),
          ),
        );
      },
    );
    if (selected == null) return;
    await _worker.setQuality(selected).catchError((_) {});
    _requestPumpSoon();
  }

  /// 将 worker 的画质枚举映射为中文展示文本。
  String _qualityLabel(String quality) {
    switch (quality) {
      case 'low':
        return '低';
      case 'medium':
        return '中';
      case 'high':
        return '高';
      case 'best':
        return '最佳';
      default:
        return '未知';
    }
  }

  /// 选择并设置缩放模式（exact_fit/no_border/no_scale/show_all）。
  Future<void> _pickScaleMode() async {
    if (!_workerReady || _swfInfo == null) return;
    String? current;
    try {
      current = await _worker.getScaleMode();
    } catch (_) {}
    if (!mounted) return;
    const options = <String>['show_all', 'no_border', 'exact_fit', 'no_scale'];
    final selected = await showCupertinoModalPopup<String>(
      context: context,
      builder: (context) {
        return CupertinoActionSheet(
          title: const Text('缩放模式'),
          actions: [
            for (final o in options)
              CupertinoActionSheetAction(
                onPressed: () => Navigator.of(context).pop(o),
                child: Text(
                  o == current ? '✓ ${_scaleModeLabel(o)}' : _scaleModeLabel(o),
                ),
              ),
          ],
          cancelButton: CupertinoActionSheetAction(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('取消'),
          ),
        );
      },
    );
    if (selected == null) return;
    await _worker.setScaleMode(selected).catchError((_) {});
    _requestPumpSoon();
  }

  /// 将 worker 的缩放模式枚举映射为中文展示文本。
  String _scaleModeLabel(String scaleMode) {
    switch (scaleMode) {
      case 'show_all':
        return '完整显示';
      case 'no_border':
        return '填满（裁切）';
      case 'exact_fit':
        return '拉伸填满';
      case 'no_scale':
        return '不缩放';
      default:
        return '未知';
    }
  }

  /// 页面退出动作（从当前 route 返回）。
  void _exit() {
    Navigator.of(context).maybePop();
  }

  @override
  /// 构建播放器页：原生 PlatformView + 平台 Surface 直出；输入系统/Surface/菜单分别封装。
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: LayoutBuilder(
        builder: (context, constraints) {
          final maxW = constraints.maxWidth;
          final maxH = constraints.maxHeight;
          final devicePixelRatio = View.of(context).devicePixelRatio;
          final stageAspect =
              _swfInfo?.aspectRatio ?? (maxH <= 0 ? 1.0 : (maxW / maxH));
          var viewW = maxW;
          var viewH = maxH;
          if (viewW > 0 &&
              viewH > 0 &&
              stageAspect.isFinite &&
              stageAspect > 0) {
            final byW = viewW / stageAspect;
            if (byW <= viewH) {
              viewH = byW;
            } else {
              viewW = viewH * stageAspect;
            }
          }

          final scaleFactor = _chooseViewportScaleFactor(
            devicePixelRatio: devicePixelRatio,
            maxW: viewW,
            maxH: viewH,
          );
          _updateViewportIfNeeded(
            maxW: viewW,
            maxH: viewH,
            scaleFactor: scaleFactor,
          );

          final viewportWidthPx =
              _lastViewportWidthPx ??
              (viewW * scaleFactor).round().clamp(1, 1 << 30);
          final viewportHeightPx =
              _lastViewportHeightPx ??
              (viewH * scaleFactor).round().clamp(1, 1 << 30);
          final fps = _recentPumpFrameTimesMicros.length < 6
              ? null
              : (() {
                  final first = _recentPumpFrameTimesMicros.first;
                  final last = _recentPumpFrameTimesMicros.last;
                  final spanMicros = last - first;
                  if (spanMicros <= 0) return null;
                  return (_recentPumpFrameTimesMicros.length - 1) *
                      1e6 /
                      spanMicros;
                })();

          Widget stageView = PlayerInputBindings(
            sendKeyDown: ({required String logicalKey}) async {
              if (_pressedPhysicalLogicalKeys.add(logicalKey)) {
                await _worker.sendKeyDown(logicalKey: logicalKey);
              }
            },
            sendKeyUp: ({required String logicalKey}) async {
              _pressedPhysicalLogicalKeys.remove(logicalKey);
              await _worker.sendKeyUp(logicalKey: logicalKey);
            },
            sendTextInput: ({required String codepoint}) =>
                _worker.sendTextInput(codepoint: codepoint),
            sendMouseMove: ({required double x, required double y}) =>
                _worker.sendMouseMove(x: x, y: y),
            sendMouseDown:
                ({required double x, required double y, required int button}) =>
                    _worker.sendMouseDown(x: x, y: y, button: button),
            sendMouseUp:
                ({required double x, required double y, required int button}) =>
                    _worker.sendMouseUp(x: x, y: y, button: button),
            sendMouseLeave: _worker.sendMouseLeave,
            setMouseInStage: ({required bool isInStage}) =>
                _worker.setMouseInStage(isInStage: isInStage),
            sendMouseWheel: ({required double deltaPixels}) =>
                _worker.sendMouseWheel(deltaPixels: deltaPixels),
            sendFocusGained: _worker.sendFocusGained,
            sendFocusLost: _worker.sendFocusLost,
            child: PlayerInputRegion(
              focusNode: _focusNode,
              enabled: _workerReady,
              scaleFactor: scaleFactor,
              viewportWidthPx: viewportWidthPx,
              viewportHeightPx: viewportHeightPx,
              fire: _fire,
              requestPumpSoon: _requestPumpSoon,
              releaseAllPressedKeys: _releaseAllPressedKeys,
              child: _useSurface()
                  ? PlayerSurfaceView(onSurfaceReady: _onSurfaceReady)
                  : (_desktopTextureId == null
                        ? const Center(
                            child: CircularProgressIndicator.adaptive(),
                          )
                        : Texture(
                            textureId: _desktopTextureId!,
                            filterQuality: FilterQuality.none,
                          )),
            ),
          );

          if (!_useSurface()) {
            stageView = ClipRect(child: stageView);
          }

          return Stack(
            children: [
              Center(
                child: SizedBox(width: viewW, height: viewH, child: stageView),
              ),
              Positioned(
                top: 0,
                right: 0,
                child: SafeArea(
                  child: PlayerMenuButton(
                    onReload: () => unawaited(_reload()),
                    onPickQuality: () => unawaited(_pickQuality()),
                    onPickScaleMode: () => unawaited(_pickScaleMode()),
                    onExit: _exit,
                  ),
                ),
              ),
              PlayerHud(fps: fps),
              if (!_showVirtualKeyboard && !_showVirtualGamepad)
                Positioned(
                  right: 10,
                  bottom: 10,
                  child: SafeArea(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.45),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: Colors.white.withValues(alpha: 0.12),
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            onPressed: _toggleVirtualGamepad,
                            icon: Icon(
                              _showVirtualGamepad
                                  ? Icons.sports_esports
                                  : Icons.sports_esports_outlined,
                              color: Colors.white,
                            ),
                            visualDensity: VisualDensity.compact,
                          ),
                          IconButton(
                            onPressed: _toggleVirtualKeyboard,
                            icon: Icon(
                              _showVirtualKeyboard
                                  ? Icons.keyboard_hide
                                  : Icons.keyboard,
                              color: Colors.white,
                            ),
                            visualDensity: VisualDensity.compact,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              Align(
                alignment: Alignment.bottomCenter,
                child: VirtualGamepad(
                  visible: _showVirtualGamepad,
                  onToggleVisible: _toggleVirtualGamepad,
                  onKeyDown: _sendVirtualKeyDown,
                  onKeyUp: _sendVirtualKeyUp,
                  store: _gamepadStore,
                  onPickKey:
                      (context, {required controlId, required current}) =>
                          _pickGamepadLogicalKey(
                            context: context,
                            controlId: controlId,
                            current: current,
                          ),
                  onSaveStore: _saveGamepadStoreFromWidget,
                ),
              ),
              Align(
                alignment: Alignment.bottomCenter,
                child: VirtualKeyboard(
                  visible: _showVirtualKeyboard,
                  onToggleVisible: _toggleVirtualKeyboard,
                  onKeyDown: _sendVirtualKeyDown,
                  onKeyUp: _sendVirtualKeyUp,
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _PendingSocketRequest {
  final BigInt requestId;
  final String host;
  final int port;

  const _PendingSocketRequest({
    required this.requestId,
    required this.host,
    required this.port,
  });
}
