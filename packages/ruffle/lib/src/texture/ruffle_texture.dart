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

class RuffleTexture {
  static const MethodChannel _channel = MethodChannel('ruffle/texture');

  /// 在平台侧创建一个可用于 Flutter `Texture` Widget 显示的 PixelBufferTexture，并返回 textureId。
  static Future<int> create() async {
    final id = await _channel.invokeMethod<int>('create');
    if (id == null) {
      throw StateError('create 返回为空');
    }
    return id;
  }

  /// 将一帧 RGBA8888 像素缓冲更新到指定 textureId，并通知平台侧新帧可用。
  static Future<void> updateRgba({
    required int textureId,
    required Uint8List rgba,
    required int width,
    required int height,
  }) async {
    await _channel.invokeMethod<void>('update_rgba', {
      'textureId': textureId,
      'rgba': rgba,
      'width': width,
      'height': height,
    });
  }

  /// 释放平台侧纹理资源，并注销该 textureId。
  static Future<void> disposeTexture({required int textureId}) async {
    await _channel.invokeMethod<void>('dispose', {
      'textureId': textureId,
    });
  }
}
