import 'dart:async';
import 'dart:isolate';

import 'package:flutter/services.dart';
import 'package:ruffle/ruffle.dart';

class RuffleWorker {
  SendPort? _sendPort;
  Isolate? _isolate;
  ReceivePort? _receivePort;
  int _nextId = 1;
  final Map<int, Completer<Map<String, Object?>>> _pending = {};

  /// worker 是否已完成启动（已拿到 SendPort，可安全发送消息）。
  bool get isStarted => _sendPort != null;

  /// 启动后台 isolate，并初始化 Rust 侧库加载。
  Future<void> start({String? storageBaseDir}) async {
    if (_isolate != null) return;
    final receivePort = ReceivePort();
    _receivePort = receivePort;
    final sendPortCompleter = Completer<SendPort>();
    _isolate = await Isolate.spawn<_RuffleWorkerInit>(
      _ruffleWorkerMain,
      _RuffleWorkerInit(
        sendPort: receivePort.sendPort,
      ),
      debugName: 'ruffle-worker',
    );

    receivePort.listen((message) {
      final currentSendPort = _sendPort;
      if (currentSendPort == null && message is SendPort) {
        _sendPort = message;
        if (!sendPortCompleter.isCompleted) {
          sendPortCompleter.complete(message);
        }
        return;
      }
      if (message is! Map) return;
      final id = message['id'];
      if (id is! int) return;
      final completer = _pending.remove(id);
      if (completer == null) return;

      final error = message['error'];
      if (error is String) {
        completer.completeError(StateError(error));
        return;
      }
      completer.complete(Map<String, Object?>.from(message['data'] as Map));
    });

    _sendPort = await sendPortCompleter.future;
    await _call('init', {'storageBaseDir': storageBaseDir});
  }

  /// 创建平台 Surface 模式 player（macOS/iOS: CoreAnimationLayer；Android: ANativeWindow），返回 header（不包含首帧像素）。
  Future<Map<String, Object?>> createFromBytesPlatformSurface({
    required Uint8List bytes,
    required String url,
    required String name,
    required int surfacePtr,
    required int width,
    required int height,
    required double scaleFactor,
  }) async {
    final ttd = TransferableTypedData.fromList([bytes]);
    return _call('create_from_bytes_platform_surface', {
      'bytes': ttd,
      'url': url,
      'name': name,
      'surfacePtr': surfacePtr,
      'width': width,
      'height': height,
      'scaleFactor': scaleFactor,
    });
  }

  /// 创建离屏渲染模式 player（Windows/Linux 等无平台 Surface 的场景），返回 header（不包含首帧像素）。
  Future<Map<String, Object?>> createFromBytesOffscreen({
    required Uint8List bytes,
    required String url,
    required String name,
    required int width,
    required int height,
    required double scaleFactor,
  }) async {
    final ttd = TransferableTypedData.fromList([bytes]);
    return _call('create_from_bytes_offscreen', {
      'bytes': ttd,
      'url': url,
      'name': name,
      'width': width,
      'height': height,
      'scaleFactor': scaleFactor,
    });
  }

  /// 推进并在需要时渲染到 Surface（SwapChain），用于 macOS 平台视图直出。
  Future<Map<String, Object?>> tickAndRenderSurface({
    required double dtMillis,
  }) async {
    return _call('tick_and_render_surface', {
      'dtMillis': dtMillis,
    });
  }

  /// 推进并在需要时渲染 + 抓取 RGBA 像素帧（离屏渲染），用于 Windows/Linux 的 Flutter 侧显示。
  Future<Map<String, Object?>> tickAndRenderOffscreen({
    required double dtMillis,
  }) async {
    return _call('tick_and_render_offscreen', {
      'dtMillis': dtMillis,
    });
  }

  /// 仅推进 player（不抓取帧），用于 UI 线程正在解码上一帧时避免逻辑停滞。
  Future<void> tickOnly({required double dtMillis}) async {
    await _call('tick_only', {
      'dtMillis': dtMillis,
    });
  }

  /// 释放当前 player（如果存在）。
  Future<void> disposePlayer() async {
    await _call('dispose_player', const {});
  }

  /// 当平台 Surface 发生变化（Android 前后台、重建窗口等）时，用新的 surface 指针重建 wgpu surface。
  Future<void> recreateSurfacePlatform({
    required int surfacePtr,
    required int width,
    required int height,
    required double scaleFactor,
  }) async {
    await _call('recreate_surface_platform', {
      'surfacePtr': surfacePtr,
      'width': width,
      'height': height,
      'scaleFactor': scaleFactor,
    });
  }

  /// 设置 player 播放状态（用于后台暂停 tick/render，但保留 player 状态）。
  Future<void> setIsPlaying({required bool isPlaying}) async {
    await _call('set_is_playing', {'isPlaying': isPlaying});
  }

  /// 获取当前 player 画质（low/medium/high/best/8x8/...），若尚未创建 player 则抛错。
  Future<String> getQuality() async {
    final result = await _call('get_quality', const {});
    final quality = result['quality'];
    if (quality is! String) {
      throw StateError('worker 返回 quality 格式错误');
    }
    return quality;
  }

  /// 设置当前 player 画质（low/medium/high/best/8x8/...），若尚未创建 player 则忽略。
  Future<void> setQuality(String quality) async {
    await _call('set_quality', {'quality': quality});
  }

  /// 设置当前 player 的 viewport（width/height 为物理像素；scaleFactor 通常为设备 DPR）。
  Future<void> setViewportDimensions({
    required int width,
    required int height,
    required double scaleFactor,
  }) async {
    await _call('set_viewport', {
      'width': width,
      'height': height,
      'scaleFactor': scaleFactor,
    });
  }

  /// 获取当前 player 缩放模式（exact_fit/no_border/no_scale/show_all）。
  Future<String> getScaleMode() async {
    final result = await _call('get_scale_mode', const {});
    final scaleMode = result['scaleMode'];
    if (scaleMode is! String) {
      throw StateError('worker 返回 scaleMode 格式错误');
    }
    return scaleMode;
  }

  /// 设置当前 player 缩放模式（exact_fit/no_border/no_scale/show_all）。
  Future<void> setScaleMode(String scaleMode) async {
    await _call('set_scale_mode', {'scaleMode': scaleMode});
  }

  /// 发送鼠标移动事件到 player（坐标为 viewport 物理像素）。
  Future<void> sendMouseMove({required double x, required double y}) async {
    await _call('mouse_move', {'x': x, 'y': y});
  }

  /// 发送鼠标按下事件到 player（button: 0=Left, 1=Right, 2=Middle）。
  Future<void> sendMouseDown({
    required double x,
    required double y,
    required int button,
  }) async {
    await _call('mouse_down', {'x': x, 'y': y, 'button': button});
  }

  /// 发送鼠标抬起事件到 player（button: 0=Left, 1=Right, 2=Middle）。
  Future<void> sendMouseUp({
    required double x,
    required double y,
    required int button,
  }) async {
    await _call('mouse_up', {'x': x, 'y': y, 'button': button});
  }

  /// 发送鼠标离开事件到 player。
  Future<void> sendMouseLeave() async {
    await _call('mouse_leave', const {});
  }

  /// 设置鼠标是否位于舞台区域内（用于正确的悬停/按钮状态/拖拽行为）。
  Future<void> setMouseInStage({required bool isInStage}) async {
    await _call('mouse_in_stage', {'isInStage': isInStage});
  }

  /// 发送鼠标滚轮事件到 player（deltaPixels：像素单位）。
  Future<void> sendMouseWheel({required double deltaPixels}) async {
    await _call('mouse_wheel', {'deltaPixels': deltaPixels});
  }

  /// 通知 player 获得焦点（对齐桌面端 window focus 行为）。
  Future<void> sendFocusGained() async {
    await _call('focus_gained', const {});
  }

  /// 通知 player 失去焦点（对齐桌面端 window focus 行为）。
  Future<void> sendFocusLost() async {
    await _call('focus_lost', const {});
  }

  /// 发送键盘按下事件到 player（logicalKey：单字符或 ArrowLeft/Enter 等）。
  Future<void> sendKeyDown({required String logicalKey}) async {
    await _call('key_down', {'logicalKey': logicalKey});
  }

  /// 发送键盘抬起事件到 player（logicalKey：单字符或 ArrowLeft/Enter 等）。
  Future<void> sendKeyUp({required String logicalKey}) async {
    await _call('key_up', {'logicalKey': logicalKey});
  }

  /// 发送文本输入事件到 player（codepoint：单字符）。
  Future<void> sendTextInput({required String codepoint}) async {
    await _call('text_input', {'codepoint': codepoint});
  }

  /// 关闭 worker isolate。
  Future<void> shutdown() async {
    try {
      if (_sendPort != null) {
        await _call('shutdown', const {});
      }
    } finally {
      for (final c in _pending.values) {
        c.completeError(StateError('worker 已关闭'));
      }
      _pending.clear();
      _receivePort?.close();
      _receivePort = null;
      _isolate?.kill(priority: Isolate.immediate);
      _isolate = null;
      _sendPort = null;
    }
  }

  Future<Map<String, Object?>> _call(String method, Map<String, Object?> params) async {
    final sendPort = _sendPort;
    if (sendPort == null) {
      throw StateError('worker 未启动');
    }
    final id = _nextId++;
    final completer = Completer<Map<String, Object?>>();
    _pending[id] = completer;
    sendPort.send({
      'id': id,
      'method': method,
      'params': params,
    });
    return completer.future;
  }
}

class _RuffleWorkerInit {
  final SendPort sendPort;

  const _RuffleWorkerInit({required this.sendPort});
}

/// worker isolate 入口：在后台线程内执行 Rust player 生命周期相关操作。
void _ruffleWorkerMain(_RuffleWorkerInit init) {
  final uiPort = init.sendPort;
  final receivePort = ReceivePort();
  uiPort.send(receivePort.sendPort);

  BigInt? playerId;
  var forceRenderNext = false;
  var surfaceEnabled = false;
  var offscreenEnabled = false;
  var isPlaying = true;
  var noRenderStreak = 0;

  Future<void> opChain = Future.value();

  receivePort.listen((message) {
    if (message is! Map) return;
    final id = message['id'];
    final method = message['method'];
    final params = message['params'];
    if (id is! int || method is! String || params is! Map) return;

    opChain = opChain
        .then((_) async {
          Future<void> replyOk(Map<String, Object?> data) async {
            uiPort.send({'id': id, 'data': data});
          }

          Future<void> replyErr(Object error) async {
            uiPort.send({'id': id, 'error': error.toString()});
          }

          try {
            if (method == 'init') {
              final storageBaseDir = params['storageBaseDir'];
              await initRust(
                storageBaseDir:
                    storageBaseDir is String && storageBaseDir.isNotEmpty
                        ? storageBaseDir
                        : null,
              );
              await replyOk(const {});
              return;
            }

            if (method == 'create_from_bytes_platform_surface') {
              final ttd = params['bytes'] as TransferableTypedData?;
              final url = params['url'] as String?;
              final name = params['name'] as String?;
              final surfacePtr = params['surfacePtr'];
              final width = params['width'];
              final height = params['height'];
              final scaleFactor = params['scaleFactor'];
              if (ttd == null ||
                  url == null ||
                  name == null ||
                  surfacePtr is! int ||
                  width is! int ||
                  height is! int ||
                  scaleFactor is! double) {
                throw StateError('参数缺失');
              }
              final bytes = ttd.materialize().asUint8List();
              if (playerId != null) {
                playerDispose(playerId: playerId!);
                playerId = null;
              }
              final newPlayerId = playerCreateFromBytesPlatformSurface(
                bytes: bytes,
                url: url,
                surfacePtr: BigInt.from(surfacePtr),
                width: width,
                height: height,
                scaleFactor: scaleFactor,
              );
              playerSetLetterbox(playerId: newPlayerId, letterbox: 'on');
              final newHeader = playerGetHeader(playerId: newPlayerId);
              playerId = newPlayerId;
              forceRenderNext = true;
              surfaceEnabled = true;
              offscreenEnabled = false;
              isPlaying = true;
              await replyOk({
                'name': name,
                'playerReady': true,
                'header': {
                  'swfVersion': newHeader.swfVersion,
                  'widthPx': newHeader.widthPx,
                  'heightPx': newHeader.heightPx,
                  'frameRate': newHeader.frameRate,
                  'numFrames': newHeader.numFrames,
                  'compression': newHeader.compression,
                  'isActionScript3': newHeader.isActionScript3,
                },
              });
              return;
            }

            if (method == 'create_from_bytes_offscreen') {
              final ttd = params['bytes'] as TransferableTypedData?;
              final url = params['url'] as String?;
              final name = params['name'] as String?;
              final width = params['width'];
              final height = params['height'];
              final scaleFactor = params['scaleFactor'];
              if (ttd == null ||
                  url == null ||
                  name == null ||
                  width is! int ||
                  height is! int ||
                  scaleFactor is! double) {
                throw StateError('参数缺失');
              }
              final bytes = ttd.materialize().asUint8List();
              if (playerId != null) {
                playerDispose(playerId: playerId!);
                playerId = null;
              }
              final newPlayerId = playerCreateFromBytesOffscreen(
                bytes: bytes,
                url: url,
                width: width,
                height: height,
                scaleFactor: scaleFactor,
              );
              playerSetLetterbox(playerId: newPlayerId, letterbox: 'on');
              final newHeader = playerGetHeader(playerId: newPlayerId);
              playerId = newPlayerId;
              forceRenderNext = true;
              surfaceEnabled = false;
              offscreenEnabled = true;
              isPlaying = true;
              noRenderStreak = 0;
              await replyOk({
                'name': name,
                'playerReady': true,
                'header': {
                  'swfVersion': newHeader.swfVersion,
                  'widthPx': newHeader.widthPx,
                  'heightPx': newHeader.heightPx,
                  'frameRate': newHeader.frameRate,
                  'numFrames': newHeader.numFrames,
                  'compression': newHeader.compression,
                  'isActionScript3': newHeader.isActionScript3,
                },
              });
              return;
            }

            if (method == 'recreate_surface_platform') {
              final surfacePtr = params['surfacePtr'];
              final width = params['width'];
              final height = params['height'];
              final scaleFactor = params['scaleFactor'];
              if (surfacePtr is! int || width is! int || height is! int || scaleFactor is! double) {
                throw StateError('recreate_surface_platform 参数错误');
              }
              final currentPlayerId = playerId;
              if (currentPlayerId == null || !surfaceEnabled) {
                await replyOk(const {});
                return;
              }
              playerRecreateSurfacePlatformSurface(
                playerId: currentPlayerId,
                surfacePtr: BigInt.from(surfacePtr),
                width: width,
                height: height,
              );
              playerSetViewportDimensions(
                playerId: currentPlayerId,
                width: width,
                height: height,
                scaleFactor: scaleFactor,
              );
              forceRenderNext = true;
              surfaceEnabled = true;
              offscreenEnabled = false;
              noRenderStreak = 0;
              await replyOk(const {});
              return;
            }

            if (method == 'set_is_playing') {
              final isPlayingParam = params['isPlaying'];
              if (isPlayingParam is! bool) {
                throw StateError('set_is_playing 参数错误');
              }
              final currentPlayerId = playerId;
              if (currentPlayerId == null) {
                await replyOk(const {});
                return;
              }
              playerSetIsPlaying(playerId: currentPlayerId, isPlaying: isPlayingParam);
              isPlaying = isPlayingParam;
              if (isPlayingParam) {
                forceRenderNext = true;
              } else {
                forceRenderNext = false;
                noRenderStreak = 0;
              }
              await replyOk(const {});
              return;
            }

            if (method == 'tick_and_render_surface') {
              final dtMillis = params['dtMillis'];
              if (dtMillis is! double) {
                throw StateError('dtMillis 参数错误');
              }
              final currentPlayerId = playerId;
              if (currentPlayerId == null || !surfaceEnabled || !isPlaying) {
                noRenderStreak = 0;
                await replyOk(const {
                  'hasFrame': false,
                  'timeTilNextFrameMillis': 16,
                  'externalUrls': <String>[],
                  'socketRequests': <Map<String, Object?>>[],
                });
                return;
              }
              final tick = playerTick(playerId: currentPlayerId, dtMillis: dtMillis);
              final externalUrls = navigatorDrainPendingExternalUrls();
              final socketRequests = navigatorDrainPendingSocketRequests()
                  .map(
                    (r) => <String, Object?>{
                      'requestId': r.requestId,
                      'host': r.host,
                      'port': r.port,
                    },
                  )
                  .toList(growable: false);
              final shouldRender = tick.needsRender || forceRenderNext;
              if (!shouldRender) {
                noRenderStreak += 1;
                final timeTilNextFrameMillis = tick.timeTilNextFrameMillis.toInt();
                if (noRenderStreak >= 30 && timeTilNextFrameMillis <= 20) {
                  playerRenderPresent(playerId: currentPlayerId);
                  noRenderStreak = 0;
                  forceRenderNext = false;
                  await replyOk({
                    'hasFrame': true,
                    'timeTilNextFrameMillis': timeTilNextFrameMillis,
                    'externalUrls': externalUrls,
                    'socketRequests': socketRequests,
                  });
                  return;
                }
                await replyOk({
                  'hasFrame': false,
                  'timeTilNextFrameMillis': timeTilNextFrameMillis,
                  'externalUrls': externalUrls,
                  'socketRequests': socketRequests,
                });
                return;
              }
              playerRenderPresent(playerId: currentPlayerId);
              forceRenderNext = false;
              noRenderStreak = 0;
              await replyOk({
                'hasFrame': true,
                'timeTilNextFrameMillis': tick.timeTilNextFrameMillis.toInt(),
                'externalUrls': externalUrls,
                'socketRequests': socketRequests,
              });
              return;
            }

            if (method == 'tick_and_render_offscreen') {
              final dtMillis = params['dtMillis'];
              if (dtMillis is! double) {
                throw StateError('dtMillis 参数错误');
              }
              final currentPlayerId = playerId;
              if (currentPlayerId == null || !offscreenEnabled || !isPlaying) {
                await replyOk(const {
                  'hasFrame': false,
                  'timeTilNextFrameMillis': 16,
                  'externalUrls': <String>[],
                  'socketRequests': <Map<String, Object?>>[],
                });
                return;
              }
              final tick = playerTick(playerId: currentPlayerId, dtMillis: dtMillis);
              final externalUrls = navigatorDrainPendingExternalUrls();
              final socketRequests = navigatorDrainPendingSocketRequests()
                  .map(
                    (r) => <String, Object?>{
                      'requestId': r.requestId,
                      'host': r.host,
                      'port': r.port,
                    },
                  )
                  .toList(growable: false);
              final shouldRender = tick.needsRender || forceRenderNext;
              if (!shouldRender) {
                await replyOk({
                  'hasFrame': false,
                  'timeTilNextFrameMillis': tick.timeTilNextFrameMillis.toInt(),
                  'externalUrls': externalUrls,
                  'socketRequests': socketRequests,
                });
                return;
              }

              final frame = playerRenderCaptureRgba(playerId: currentPlayerId);
              forceRenderNext = false;
              await replyOk({
                'hasFrame': true,
                'timeTilNextFrameMillis': tick.timeTilNextFrameMillis.toInt(),
                'externalUrls': externalUrls,
                'socketRequests': socketRequests,
                'width': frame.width,
                'height': frame.height,
                'rgba': TransferableTypedData.fromList([frame.rgba]),
              });
              return;
            }

            if (method == 'tick_only') {
              final dtMillis = params['dtMillis'];
              if (dtMillis is! double) {
                throw StateError('dtMillis 参数错误');
              }
              final currentPlayerId = playerId;
              if (currentPlayerId == null || !isPlaying) {
                await replyOk(const {});
                return;
              }
              final tick = playerTick(playerId: currentPlayerId, dtMillis: dtMillis);
              if (tick.needsRender) {
                forceRenderNext = true;
              }
              await replyOk(const {});
              return;
            }

            if (method == 'set_viewport') {
              final width = params['width'];
              final height = params['height'];
              final scaleFactor = params['scaleFactor'];
              if (width is! int || height is! int || scaleFactor is! double) {
                throw StateError('set_viewport 参数错误');
              }
              final currentPlayerId = playerId;
              if (currentPlayerId == null) {
                await replyOk(const {});
                return;
              }
              playerSetViewportDimensions(
                playerId: currentPlayerId,
                width: width,
                height: height,
                scaleFactor: scaleFactor,
              );
              forceRenderNext = true;
              await replyOk(const {});
              return;
            }

            if (method == 'get_scale_mode') {
              final currentPlayerId = playerId;
              if (currentPlayerId == null) {
                throw StateError('player 未创建');
              }
              final scaleMode = playerScaleMode(playerId: currentPlayerId);
              await replyOk({'scaleMode': scaleMode});
              return;
            }

            if (method == 'set_scale_mode') {
              final scaleMode = params['scaleMode'];
              if (scaleMode is! String) {
                throw StateError('scaleMode 参数错误');
              }
              final currentPlayerId = playerId;
              if (currentPlayerId == null) {
                await replyOk(const {});
                return;
              }
              playerSetScaleMode(playerId: currentPlayerId, scaleMode: scaleMode);
              forceRenderNext = true;
              await replyOk(const {});
              return;
            }

            if (method == 'get_quality') {
              final currentPlayerId = playerId;
              if (currentPlayerId == null) {
                throw StateError('player 未创建');
              }
              final quality = playerQuality(playerId: currentPlayerId);
              await replyOk({'quality': quality});
              return;
            }

            if (method == 'set_quality') {
              final quality = params['quality'];
              if (quality is! String) {
                throw StateError('quality 参数错误');
              }
              final currentPlayerId = playerId;
              if (currentPlayerId == null) {
                await replyOk(const {});
                return;
              }
              playerSetQuality(playerId: currentPlayerId, quality: quality);
              forceRenderNext = true;
              await replyOk(const {});
              return;
            }

            if (method == 'mouse_move') {
              final x = params['x'];
              final y = params['y'];
              if (x is! double || y is! double) {
                throw StateError('mouse_move 参数错误');
              }
              final currentPlayerId = playerId;
              if (currentPlayerId == null) {
                await replyOk(const {});
                return;
              }
              playerMouseMove(playerId: currentPlayerId, x: x, y: y);
              forceRenderNext = true;
              await replyOk(const {});
              return;
            }

            if (method == 'mouse_down') {
              final x = params['x'];
              final y = params['y'];
              final button = params['button'];
              if (x is! double || y is! double || button is! int) {
                throw StateError('mouse_down 参数错误');
              }
              final currentPlayerId = playerId;
              if (currentPlayerId == null) {
                await replyOk(const {});
                return;
              }
              playerMouseDown(playerId: currentPlayerId, x: x, y: y, button: button);
              forceRenderNext = true;
              await replyOk(const {});
              return;
            }

            if (method == 'mouse_up') {
              final x = params['x'];
              final y = params['y'];
              final button = params['button'];
              if (x is! double || y is! double || button is! int) {
                throw StateError('mouse_up 参数错误');
              }
              final currentPlayerId = playerId;
              if (currentPlayerId == null) {
                await replyOk(const {});
                return;
              }
              playerMouseUp(playerId: currentPlayerId, x: x, y: y, button: button);
              forceRenderNext = true;
              await replyOk(const {});
              return;
            }

            if (method == 'mouse_leave') {
              final currentPlayerId = playerId;
              if (currentPlayerId == null) {
                await replyOk(const {});
                return;
              }
              playerMouseLeave(playerId: currentPlayerId);
              forceRenderNext = true;
              await replyOk(const {});
              return;
            }

            if (method == 'mouse_in_stage') {
              final isInStage = params['isInStage'];
              if (isInStage is! bool) {
                throw StateError('mouse_in_stage 参数错误');
              }
              final currentPlayerId = playerId;
              if (currentPlayerId == null) {
                await replyOk(const {});
                return;
              }
              playerSetMouseInStage(playerId: currentPlayerId, isInStage: isInStage);
              forceRenderNext = true;
              await replyOk(const {});
              return;
            }

            if (method == 'mouse_wheel') {
              final deltaPixels = params['deltaPixels'];
              if (deltaPixels is! double) {
                throw StateError('mouse_wheel 参数错误');
              }
              final currentPlayerId = playerId;
              if (currentPlayerId == null) {
                await replyOk(const {});
                return;
              }
              playerMouseWheelPixels(playerId: currentPlayerId, deltaPixels: deltaPixels);
              forceRenderNext = true;
              await replyOk(const {});
              return;
            }

            if (method == 'focus_gained') {
              final currentPlayerId = playerId;
              if (currentPlayerId == null) {
                await replyOk(const {});
                return;
              }
              playerFocusGained(playerId: currentPlayerId);
              forceRenderNext = true;
              await replyOk(const {});
              return;
            }

            if (method == 'focus_lost') {
              final currentPlayerId = playerId;
              if (currentPlayerId == null) {
                await replyOk(const {});
                return;
              }
              playerFocusLost(playerId: currentPlayerId);
              forceRenderNext = true;
              await replyOk(const {});
              return;
            }

            if (method == 'key_down') {
              final logicalKey = params['logicalKey'];
              if (logicalKey is! String) {
                throw StateError('key_down 参数错误');
              }
              final currentPlayerId = playerId;
              if (currentPlayerId == null) {
                await replyOk(const {});
                return;
              }
              playerKeyDown(playerId: currentPlayerId, logicalKey: logicalKey);
              forceRenderNext = true;
              await replyOk(const {});
              return;
            }

            if (method == 'key_up') {
              final logicalKey = params['logicalKey'];
              if (logicalKey is! String) {
                throw StateError('key_up 参数错误');
              }
              final currentPlayerId = playerId;
              if (currentPlayerId == null) {
                await replyOk(const {});
                return;
              }
              playerKeyUp(playerId: currentPlayerId, logicalKey: logicalKey);
              forceRenderNext = true;
              await replyOk(const {});
              return;
            }

            if (method == 'text_input') {
              final codepoint = params['codepoint'];
              if (codepoint is! String) {
                throw StateError('text_input 参数错误');
              }
              final currentPlayerId = playerId;
              if (currentPlayerId == null) {
                await replyOk(const {});
                return;
              }
              playerTextInput(playerId: currentPlayerId, codepoint: codepoint);
              forceRenderNext = true;
              await replyOk(const {});
              return;
            }

            if (method == 'dispose_player') {
              if (playerId != null) {
                playerDispose(playerId: playerId!);
              }
              playerId = null;
              await replyOk(const {});
              return;
            }

            if (method == 'shutdown') {
              if (playerId != null) {
                playerDispose(playerId: playerId!);
              }
              playerId = null;
              await replyOk(const {});
              receivePort.close();
              return;
            }

            throw StateError('未知方法: $method');
          } catch (e) {
            await replyErr(e);
          }
        })
        .catchError((_) {});
  });
}
