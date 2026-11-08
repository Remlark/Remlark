import Cocoa
import FlutterMacOS

class MainFlutterWindow: NSWindow {
  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    self.contentViewController = flutterViewController

    // 窗口尺寸：默认 1280x820，最小 960x640（与 lib/app/window_config.dart 保持一致）。
    // 屏幕较小时默认尺寸不超过可用区域。
    let minSize = NSSize(width: 960, height: 640)
    var size = NSSize(width: 1280, height: 820)
    if let visible = (self.screen ?? NSScreen.main)?.visibleFrame {
      size.width = max(minSize.width, min(size.width, visible.width - 40))
      size.height = max(minSize.height, min(size.height, visible.height - 40))
    }
    self.contentMinSize = minSize
    self.setContentSize(size)
    self.center()
    // 记住用户调整后的窗口位置与大小
    self.setFrameAutosaveName("RemlarkMainWindow")
    self.title = "Remlark"

    RegisterGeneratedPlugins(registry: flutterViewController)
    LazyFilePasteboard.shared.attach(messenger: flutterViewController.engine.binaryMessenger)
    FileDragSource.shared.attach(controller: flutterViewController)

    // 启动完成后主动激活应用并设为 key window：
    // 从终端直接运行可执行文件（flutter run / make run）时不经过 LaunchServices，
    // 系统不一定把新进程切到前台，窗口会出现但拿不到焦点
    NotificationCenter.default.addObserver(
      forName: NSApplication.didFinishLaunchingNotification, object: nil, queue: .main
    ) { [weak self] _ in
      self?.activateOnLaunch()
    }

    super.awakeFromNib()
  }

  /// 将应用切为常规前台应用并激活主窗口
  private func activateOnLaunch() {
    NSApp.setActivationPolicy(.regular)
    if #available(macOS 14.0, *) {
      NSApp.activate()
    } else {
      NSApp.activate(ignoringOtherApps: true)
    }
    makeKeyAndOrderFront(nil)
  }
}

/// 延迟提供文件的剪贴板（VNC 远程复制的文件）：复制时只放入占位项，
/// 本地粘贴时系统回调数据提供者，再经通道请求 Dart 下载并返回本地文件路径。
/// 通道 remlark/lazy_pasteboard：
/// - offer(names: [String], ids: [String]) -> Int：写入占位项，返回剪贴板 changeCount
/// - ownsClipboard() -> Bool：剪贴板当前内容是否为本程序放入的占位项（读取占位项会触发下载，需先判断）
/// - provide(id: String) -> String?：原生调用 Dart，下载远程文件并返回本地路径
class LazyFilePasteboard: NSObject, NSPasteboardItemDataProvider {
  static let shared = LazyFilePasteboard()

  /// 占位项中保存远程文件标识的私有类型
  private let idType = NSPasteboard.PasteboardType("com.remlark.remote-file-id")
  private var channel: FlutterMethodChannel?
  private var offeredChangeCount = -1

  /// 单个文件等待下载的最长时间
  private let timeout: TimeInterval = 600

  func attach(messenger: FlutterBinaryMessenger) {
    let ch = FlutterMethodChannel(name: "remlark/lazy_pasteboard", binaryMessenger: messenger)
    ch.setMethodCallHandler { [weak self] call, result in
      guard let self = self else { return }
      switch call.method {
      case "offer":
        let args = call.arguments as? [String: Any] ?? [:]
        let ids = args["ids"] as? [String] ?? []
        result(self.offer(ids: ids))
      case "ownsClipboard":
        result(NSPasteboard.general.changeCount == self.offeredChangeCount)
      default:
        result(FlutterMethodNotImplemented)
      }
    }
    channel = ch
  }

  /// 写入占位项：每个文件一项，声明文件 URL 类型并由本对象延迟提供
  private func offer(ids: [String]) -> Int {
    let pb = NSPasteboard.general
    pb.clearContents()
    let items: [NSPasteboardItem] = ids.map { id in
      let item = NSPasteboardItem()
      item.setString(id, forType: idType)
      item.setDataProvider(self, forTypes: [.fileURL])
      return item
    }
    pb.writeObjects(items)
    offeredChangeCount = pb.changeCount
    return offeredChangeCount
  }

  /// 系统在粘贴时回调：请求 Dart 下载，等待期间继续运行主线程消息循环（Dart 与平台线程合并，下载在其中进行）
  func pasteboard(_ pasteboard: NSPasteboard?, item: NSPasteboardItem, provideDataForType type: NSPasteboard.PasteboardType) {
    guard type == .fileURL, let id = item.string(forType: idType), let ch = channel else { return }
    var done = false
    var path: String?
    ch.invokeMethod("provide", arguments: id) { r in
      path = r as? String
      done = true
    }
    let deadline = Date().addingTimeInterval(timeout)
    while !done && Date() < deadline {
      RunLoop.current.run(mode: .default, before: Date(timeIntervalSinceNow: 0.02))
    }
    if let p = path {
      item.setString(URL(fileURLWithPath: p).absoluteString, forType: .fileURL)
    }
  }

  /// 应用退出等情况下剪贴板仍持有占位项：系统会在此时要求提供全部数据，这里放弃（不在退出时下载）
  func pasteboardFinishedWithDataProvider(_ pasteboard: NSPasteboard) {}
}
