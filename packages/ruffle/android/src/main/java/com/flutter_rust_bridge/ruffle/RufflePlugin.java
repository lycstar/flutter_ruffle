package com.flutter_rust_bridge.ruffle;

import android.content.Context;
import android.view.Surface;
import android.view.SurfaceHolder;
import android.view.SurfaceView;

import androidx.annotation.NonNull;

import java.util.Map;
import java.util.concurrent.ConcurrentHashMap;

import io.flutter.embedding.engine.plugins.FlutterPlugin;
import io.flutter.plugin.common.MethodCall;
import io.flutter.plugin.common.MethodChannel;
import io.flutter.plugin.common.MethodChannel.Result;
import io.flutter.plugin.common.StandardMessageCodec;
import io.flutter.plugin.platform.PlatformView;
import io.flutter.plugin.platform.PlatformViewFactory;

public final class RufflePlugin implements FlutterPlugin, MethodChannel.MethodCallHandler {
  private static final String VIEW_TYPE = "ruffle/surface";
  private static final String CHANNEL_NAME = "ruffle/surface";

  private MethodChannel channel;
  private final ConcurrentHashMap<Long, RuffleSurfacePlatformView> surfaceViews = new ConcurrentHashMap<>();

  @Override
  public void onAttachedToEngine(@NonNull FlutterPluginBinding binding) {
    System.loadLibrary("ruffle");
    RuffleNative.init(binding.getApplicationContext());
    channel = new MethodChannel(binding.getBinaryMessenger(), CHANNEL_NAME);
    channel.setMethodCallHandler(this);
    binding
        .getPlatformViewRegistry()
        .registerViewFactory(
            VIEW_TYPE,
            new RuffleSurfaceViewFactory(
                binding.getApplicationContext(),
                (viewId, view) -> surfaceViews.put(viewId, view)));
  }

  @Override
  public void onDetachedFromEngine(@NonNull FlutterPluginBinding binding) {
    if (channel != null) {
      channel.setMethodCallHandler(null);
      channel = null;
    }
    for (RuffleSurfacePlatformView view : surfaceViews.values()) {
      view.dispose();
    }
    surfaceViews.clear();
  }

  @Override
  public void onMethodCall(@NonNull MethodCall call, @NonNull Result result) {
    switch (call.method) {
      case "get_layer_ptr":
        handleGetSurfacePtr(call, result);
        break;
      case "dispose_view":
        handleDisposeView(call, result);
        break;
      default:
        result.notImplemented();
        break;
    }
  }

  /** 获取 PlatformView 对应的 surface 指针（Android: ANativeWindow*）。未就绪时返回 0。 */
  private void handleGetSurfacePtr(@NonNull MethodCall call, @NonNull Result result) {
    Object argsObj = call.arguments;
    if (!(argsObj instanceof Map)) {
      result.error("bad_args", "get_layer_ptr 参数错误", null);
      return;
    }
    @SuppressWarnings("unchecked")
    Map<String, Object> args = (Map<String, Object>) argsObj;
    Object viewIdObj = args.get("viewId");
    if (!(viewIdObj instanceof Number)) {
      result.error("bad_args", "get_layer_ptr 参数错误", null);
      return;
    }
    long viewId = ((Number) viewIdObj).longValue();
    RuffleSurfacePlatformView view = surfaceViews.get(viewId);
    if (view == null) {
      result.error("not_found", "surface view 不存在", null);
      return;
    }
    result.success(view.nativeWindowPtr());
  }

  /** 通知插件侧释放与 viewId 关联的资源缓存。 */
  private void handleDisposeView(@NonNull MethodCall call, @NonNull Result result) {
    Object argsObj = call.arguments;
    if (!(argsObj instanceof Map)) {
      result.error("bad_args", "dispose_view 参数错误", null);
      return;
    }
    @SuppressWarnings("unchecked")
    Map<String, Object> args = (Map<String, Object>) argsObj;
    Object viewIdObj = args.get("viewId");
    if (!(viewIdObj instanceof Number)) {
      result.error("bad_args", "dispose_view 参数错误", null);
      return;
    }
    long viewId = ((Number) viewIdObj).longValue();
    RuffleSurfacePlatformView view = surfaceViews.remove(viewId);
    if (view != null) {
      view.dispose();
    }
    result.success(null);
  }

  private interface OnCreate {
    void onCreate(long viewId, RuffleSurfacePlatformView view);
  }

  private static final class RuffleSurfaceViewFactory extends PlatformViewFactory {
    private final Context applicationContext;
    private final OnCreate onCreate;

    /** 创建 PlatformViewFactory，并在平台视图创建时回调（用于插件侧缓存 surface 指针）。 */
    RuffleSurfaceViewFactory(@NonNull Context applicationContext, @NonNull OnCreate onCreate) {
      super(StandardMessageCodec.INSTANCE);
      this.applicationContext = applicationContext;
      this.onCreate = onCreate;
    }

    @NonNull
    @Override
    public PlatformView create(@NonNull Context context, int viewId, Object args) {
      RuffleSurfacePlatformView view = new RuffleSurfacePlatformView(applicationContext);
      onCreate.onCreate((long) viewId, view);
      return view;
    }
  }

  private static final class RuffleSurfacePlatformView implements PlatformView, SurfaceHolder.Callback {
    private final SurfaceView surfaceView;
    private long nativeWindowPtr = 0L;
    private Surface lastSurface = null;
    private boolean surfaceValid = false;

    /** 创建一个 SurfaceView，用于 Rust(wgpu) 绑定并直接呈现。 */
    RuffleSurfacePlatformView(@NonNull Context applicationContext) {
      surfaceView = new SurfaceView(applicationContext);
      surfaceView.getHolder().addCallback(this);
    }

    long nativeWindowPtr() {
      if (!surfaceValid) {
        return 0L;
      }
      return nativeWindowPtr;
    }

    @NonNull
    @Override
    public android.view.View getView() {
      return surfaceView;
    }

    @Override
    public void dispose() {
      surfaceView.getHolder().removeCallback(this);
      releaseNativeWindowIfNeeded();
    }

    @Override
    public void surfaceCreated(@NonNull SurfaceHolder holder) {
      updateNativeWindow(holder.getSurface());
    }

    @Override
    public void surfaceChanged(@NonNull SurfaceHolder holder, int format, int width, int height) {
      updateNativeWindow(holder.getSurface());
    }

    @Override
    public void surfaceDestroyed(@NonNull SurfaceHolder holder) {
      surfaceValid = false;
      lastSurface = null;
      releaseNativeWindowIfNeeded();
    }

    /** 在 Surface 创建/变化时更新 ANativeWindow 指针；Surface 销毁时由 surfaceDestroyed 释放。 */
    private void updateNativeWindow(Surface surface) {
      if (surface == null || !surface.isValid()) {
        surfaceValid = false;
        lastSurface = null;
        releaseNativeWindowIfNeeded();
        return;
      }

      surfaceValid = true;

      if (lastSurface != surface) {
        lastSurface = surface;
        releaseNativeWindowIfNeeded();
      }

      if (nativeWindowPtr == 0L) {
        nativeWindowPtr = RuffleNative.acquireNativeWindowFromSurface(surface);
      }
    }

    private void releaseNativeWindowIfNeeded() {
      long ptr = nativeWindowPtr;
      nativeWindowPtr = 0L;
      if (ptr != 0L) {
        RuffleNative.releaseNativeWindow(ptr);
      }
    }
  }
}
