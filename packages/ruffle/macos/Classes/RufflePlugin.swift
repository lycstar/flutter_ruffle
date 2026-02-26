import Cocoa
import FlutterMacOS
import Metal
import QuartzCore

final class RuffleSurfaceNSView: NSView {
  private let metalLayer: CAMetalLayer

  /// 创建一个以 CAMetalLayer 作为 backing layer 的 NSView，用于 wgpu Surface 绑定。
  override init(frame frameRect: NSRect) {
    let layer = CAMetalLayer()
    layer.device = MTLCreateSystemDefaultDevice()
    layer.pixelFormat = .bgra8Unorm
    layer.framebufferOnly = true
    layer.isOpaque = true
    self.metalLayer = layer
    super.init(frame: frameRect)
    wantsLayer = true
    self.layer = layer
    updateLayerSize()
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  override func layout() {
    super.layout()
    updateLayerSize()
  }

  private func updateLayerSize() {
    metalLayer.frame = bounds
    let scale = window?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 1.0
    metalLayer.contentsScale = scale
    let w = max(1.0, bounds.width * scale)
    let h = max(1.0, bounds.height * scale)
    metalLayer.drawableSize = CGSize(width: w, height: h)
  }

  override func viewDidMoveToWindow() {
    super.viewDidMoveToWindow()
    updateLayerSize()
  }

  override func viewDidChangeBackingProperties() {
    super.viewDidChangeBackingProperties()
    updateLayerSize()
  }

  /// 获取当前 CAMetalLayer 的原生指针（传给 Rust 侧用于创建 wgpu Surface）。
  func layerPointer() -> UInt64 {
    UInt64(UInt(bitPattern: Unmanaged.passUnretained(metalLayer).toOpaque()))
  }
}

final class RuffleSurfacePlatformViewFactory: NSObject, FlutterPlatformViewFactory {
  private let onCreate: (Int64, RuffleSurfaceNSView) -> Void

  /// 创建 PlatformViewFactory，并在平台视图创建时回调（用于插件侧缓存 layer 指针）。
  init(onCreate: @escaping (Int64, RuffleSurfaceNSView) -> Void) {
    self.onCreate = onCreate
    super.init()
  }

  func createArgsCodec() -> (FlutterMessageCodec & NSObjectProtocol)? {
    FlutterStandardMessageCodec.sharedInstance()
  }

  func create(withViewIdentifier viewId: Int64, arguments args: Any?) -> NSView {
    let v = RuffleSurfaceNSView(frame: .zero)
    onCreate(viewId, v)
    return v
  }
}

public final class RufflePlugin: NSObject, FlutterPlugin {
  private static let surfaceChannelName = "ruffle/surface"

  private let surfaceChannel: FlutterMethodChannel
  private var surfaceViews: [Int64: RuffleSurfaceNSView] = [:]

  init(surfaceChannel: FlutterMethodChannel) {
    self.surfaceChannel = surfaceChannel
  }

  public static func register(with registrar: FlutterPluginRegistrar) {
    let surfaceChannel = FlutterMethodChannel(name: surfaceChannelName, binaryMessenger: registrar.messenger)
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
      let ptr = view.layerPointer()
      result(Int64(bitPattern: ptr))

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
