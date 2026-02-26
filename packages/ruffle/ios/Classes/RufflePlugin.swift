import Flutter
import Metal
import QuartzCore
import UIKit

final class RuffleSurfaceUIView: UIView {
  /// 将 UIView 的 backing layer 指定为 CAMetalLayer，供 Rust(wgpu) 直接绑定并呈现。
  override class var layerClass: AnyClass {
    CAMetalLayer.self
  }

  private var metalLayer: CAMetalLayer {
    layer as! CAMetalLayer
  }

  /// 初始化 Surface 视图，并配置 CAMetalLayer 的基础属性。
  override init(frame: CGRect) {
    super.init(frame: frame)
    isOpaque = true
    contentMode = .redraw
    configureMetalLayer()
    updateLayerSize()
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  override func layoutSubviews() {
    super.layoutSubviews()
    updateLayerSize()
  }

  override func didMoveToWindow() {
    super.didMoveToWindow()
    updateLayerSize()
  }

  private func configureMetalLayer() {
    metalLayer.device = MTLCreateSystemDefaultDevice()
    metalLayer.pixelFormat = .bgra8Unorm
    metalLayer.framebufferOnly = true
    metalLayer.isOpaque = true
  }

  private func updateLayerSize() {
    let scale = window?.screen.scale ?? UIScreen.main.scale
    metalLayer.frame = bounds
    metalLayer.contentsScale = scale
    let w = max(1.0, bounds.width * scale)
    let h = max(1.0, bounds.height * scale)
    metalLayer.drawableSize = CGSize(width: w, height: h)
  }

  /// 获取当前 CAMetalLayer 的原生指针（传给 Rust 侧用于创建 wgpu Surface）。
  func layerPointer() -> UInt64 {
    UInt64(UInt(bitPattern: Unmanaged.passUnretained(metalLayer).toOpaque()))
  }
}

final class RuffleSurfacePlatformView: NSObject, FlutterPlatformView {
  private let surfaceView: RuffleSurfaceUIView

  /// 创建一个基于 CAMetalLayer 的平台视图实例。
  init(frame: CGRect) {
    surfaceView = RuffleSurfaceUIView(frame: frame)
    super.init()
  }

  func view() -> UIView {
    surfaceView
  }

  /// 获取 Surface 对应的 layer 指针（iOS: CAMetalLayer*）。
  func layerPointer() -> UInt64 {
    surfaceView.layerPointer()
  }
}

final class RuffleSurfacePlatformViewFactory: NSObject, FlutterPlatformViewFactory {
  private let onCreate: (Int64, RuffleSurfacePlatformView) -> Void

  /// 创建 PlatformViewFactory，并在平台视图创建时回调（用于插件侧缓存 layer 指针）。
  init(onCreate: @escaping (Int64, RuffleSurfacePlatformView) -> Void) {
    self.onCreate = onCreate
    super.init()
  }

  func createArgsCodec() -> FlutterMessageCodec & NSObjectProtocol {
    FlutterStandardMessageCodec.sharedInstance()
  }

  func create(
    withFrame frame: CGRect,
    viewIdentifier viewId: Int64,
    arguments args: Any?
  ) -> FlutterPlatformView {
    let v = RuffleSurfacePlatformView(frame: frame)
    onCreate(viewId, v)
    return v
  }
}

public final class RufflePlugin: NSObject, FlutterPlugin {
  private static let surfaceChannelName = "ruffle/surface"
  private let surfaceChannel: FlutterMethodChannel
  private var surfaceViews: [Int64: RuffleSurfacePlatformView] = [:]

  init(surfaceChannel: FlutterMethodChannel) {
    self.surfaceChannel = surfaceChannel
  }

  public static func register(with registrar: FlutterPluginRegistrar) {
    let surfaceChannel = FlutterMethodChannel(
      name: surfaceChannelName,
      binaryMessenger: registrar.messenger()
    )
    let plugin = RufflePlugin(surfaceChannel: surfaceChannel)
    registrar.addMethodCallDelegate(plugin, channel: surfaceChannel)
    registrar.register(
      RuffleSurfacePlatformViewFactory(onCreate: { viewId, view in
        plugin.surfaceViews[viewId] = view
      }),
      withId: "ruffle/surface"
    )
  }

  public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "get_layer_ptr":
      guard let args = call.arguments as? [String: Any],
            let viewId = args["viewId"] as? Int64 else {
        result(FlutterError(code: "bad_args", message: "get_layer_ptr 参数错误", details: nil))
        return
      }
      guard let view = surfaceViews[viewId] else {
        result(FlutterError(code: "not_found", message: "surface view 不存在", details: nil))
        return
      }
      result(Int64(bitPattern: view.layerPointer()))

    case "dispose_view":
      guard let args = call.arguments as? [String: Any],
            let viewId = args["viewId"] as? Int64 else {
        result(FlutterError(code: "bad_args", message: "dispose_view 参数错误", details: nil))
        return
      }
      surfaceViews.removeValue(forKey: viewId)
      result(nil)

    default:
      result(FlutterMethodNotImplemented)
    }
  }
}
