import Cocoa
import FlutterMacOS

@main
class AppDelegate: FlutterAppDelegate {
  /// 从当前应用包刷新 Dock 图标，避免开发启动或升级后继续显示系统缓存中的旧图标。
  override func applicationDidFinishLaunching(_ notification: Notification) {
    super.applicationDidFinishLaunching(notification)
    ApplicationIcon.refresh()
  }

  /// 关闭最后一个窗口时退出应用。
  override func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
    return true
  }

  /// 支持 macOS 安全状态恢复。
  override func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
    return true
  }
}
