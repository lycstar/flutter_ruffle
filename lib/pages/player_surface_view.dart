import 'dart:async';
import 'dart:io';

import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:ruffle/ruffle.dart';

class PlayerSurfaceReady {
  final int viewId;
  final int surfacePtr;

  const PlayerSurfaceReady({required this.viewId, required this.surfacePtr});
}

class PlayerSurfaceView extends StatefulWidget {
  final ValueChanged<PlayerSurfaceReady> onSurfaceReady;

  const PlayerSurfaceView({
    super.key,
    required this.onSurfaceReady,
  });

  @override
  /// 创建平台 Surface 视图组件状态。
  State<PlayerSurfaceView> createState() => _PlayerSurfaceViewState();
}

class _PlayerSurfaceViewState extends State<PlayerSurfaceView> {
  /// 构建平台 Surface 视图：macOS=AppKitView，iOS=UiKitView，Android=AndroidView。
  @override
  Widget build(BuildContext context) {
    Future<void> onCreated(int id) async {
      if (!mounted) return;
      final ptr = await _resolveSurfacePtrWithRetry(viewId: id);
      if (!mounted) return;
      widget.onSurfaceReady(PlayerSurfaceReady(viewId: id, surfacePtr: ptr));
    }

    if (Platform.isMacOS) {
      return AppKitView(
        viewType: RuffleSurface.viewType,
        layoutDirection: TextDirection.ltr,
        creationParams: const <String, dynamic>{},
        creationParamsCodec: const StandardMessageCodec(),
        onPlatformViewCreated: onCreated,
      );
    }
    if (Platform.isIOS) {
      return UiKitView(
        viewType: RuffleSurface.viewType,
        layoutDirection: TextDirection.ltr,
        creationParams: const <String, dynamic>{},
        creationParamsCodec: const StandardMessageCodec(),
        onPlatformViewCreated: onCreated,
        hitTestBehavior: PlatformViewHitTestBehavior.transparent,
      );
    }
    if (Platform.isAndroid) {
      return AndroidView(
        viewType: RuffleSurface.viewType,
        layoutDirection: TextDirection.ltr,
        creationParams: const <String, dynamic>{},
        creationParamsCodec: const StandardMessageCodec(),
        onPlatformViewCreated: onCreated,
        hitTestBehavior: PlatformViewHitTestBehavior.transparent,
      );
    }
    return const SizedBox.shrink();
  }

  /// 获取平台侧 surface 指针（可能在视图创建后短时间内仍未就绪），带重试以提升稳定性。
  Future<int> _resolveSurfacePtrWithRetry({required int viewId}) async {
    const maxAttempts = 120;
    var lastNonZero = 0;
    var stableCount = 0;
    for (var attempt = 0; attempt < maxAttempts; attempt++) {
      final ptr = await RuffleSurface.getLayerPtr(viewId: viewId);
      if (ptr != 0) {
        if (ptr == lastNonZero) {
          stableCount += 1;
        } else {
          lastNonZero = ptr;
          stableCount = 1;
        }
        if (stableCount >= 3) {
          return ptr;
        }
      }
      await Future<void>.delayed(const Duration(milliseconds: 16));
    }
    throw StateError('surface 指针获取超时');
  }
}
