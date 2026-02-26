import 'package:flutter/services.dart';

class RuffleSurface {
  static const String viewType = 'ruffle/surface';
  static const MethodChannel _channel = MethodChannel('ruffle/surface');

  /// 获取平台视图的渲染目标指针（用于 Rust wgpu surface 绑定）。
  ///
  /// - macOS/iOS: CAMetalLayer（CoreAnimationLayer）
  /// - Android: ANativeWindow
  static Future<int> getLayerPtr({required int viewId}) async {
    final ptr = await _channel.invokeMethod<int>('get_layer_ptr', {
      'viewId': viewId,
    });
    if (ptr == null) {
      throw StateError('get_layer_ptr 返回为空');
    }
    return ptr;
  }

  /// 通知平台侧释放与 viewId 关联的资源（避免插件侧缓存泄漏）。
  static Future<void> disposeView({required int viewId}) async {
    await _channel.invokeMethod<void>('dispose_view', {
      'viewId': viewId,
    });
  }
}
