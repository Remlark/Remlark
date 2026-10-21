import Cocoa

/// macOS 应用图标实现：直接读取当前包资源，不使用 LaunchServices 的历史图标缓存。
enum ApplicationIcon {
  /// 刷新运行中的 Dock 图标；资源缺失时保留系统图标，不影响应用启动。
  @discardableResult
  static func refresh(in application: NSApplication = .shared, bundle: Bundle = .main) -> Bool {
    guard let url = bundle.url(forResource: "AppIcon", withExtension: "icns"),
          let image = NSImage(contentsOf: url), image.isValid else {
      return false
    }
    application.applicationIconImage = image
    return true
  }
}
