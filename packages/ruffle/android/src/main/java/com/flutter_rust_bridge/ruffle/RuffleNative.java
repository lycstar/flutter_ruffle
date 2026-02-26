package com.flutter_rust_bridge.ruffle;

import android.content.Context;
import android.view.Surface;

final class RuffleNative {
  private RuffleNative() {}

  static native void init(Context context);

  /** 将 Java Surface 转换为 ANativeWindow 指针，并在 native 侧持有引用（需调用 releaseNativeWindow 释放）。 */
  static native long acquireNativeWindowFromSurface(Surface surface);

  /** 释放由 acquireNativeWindowFromSurface 获取的 ANativeWindow 引用。 */
  static native void releaseNativeWindow(long nativeWindowPtr);
}
