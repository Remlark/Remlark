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

    super.awakeFromNib()
  }
}
