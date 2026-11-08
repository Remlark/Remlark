import Cocoa
import FlutterMacOS
import UniformTypeIdentifiers

/// 把 SFTP 远程文件拖到 Finder：应用内拖动离开窗口时由 Dart 调用 start，
/// 每个顶层文件 / 目录生成一个 NSFilePromiseProvider，放下后 Finder 给出目标路径，再经通道请求 Dart 下载。
/// 通道 remlark/file_drag（协议与 lib/utils/file_drag_out/file_drag_out_channel.dart 一致）：
/// - start(session: Int, entries: [{path, isDir, size}]) -> Bool：开始系统拖动（鼠标需仍按下）
/// - write(session, index, path)：原生调 Dart，把第 index 项下载到 path，完成后回复，失败回复 FlutterError
/// - ended(session)：原生调 Dart，拖动结束
class FileDragSource: NSObject, NSDraggingSource, NSFilePromiseProviderDelegate {
  static let shared = FileDragSource()

  private var channel: FlutterMethodChannel?
  private weak var controller: FlutterViewController?

  /// 当前系统拖动的会话号（同一时间只有一次拖动）
  private var activeSession = 0

  /// promise 中保存的会话、序号与文件名
  private struct PromiseInfo {
    let session: Int
    let index: Int
    let name: String
  }

  func attach(controller: FlutterViewController) {
    self.controller = controller
    let ch = FlutterMethodChannel(name: "remlark/file_drag", binaryMessenger: controller.engine.binaryMessenger)
    ch.setMethodCallHandler { [weak self] call, result in
      guard let self = self, call.method == "start" else {
        result(FlutterMethodNotImplemented)
        return
      }
      let args = call.arguments as? [String: Any] ?? [:]
      let session = args["session"] as? Int ?? 0
      let entries = args["entries"] as? [[String: Any]] ?? []
      result(self.start(session: session, entries: entries))
    }
    channel = ch
  }

  /// 开始系统拖动：左键已松开、没有窗口或没有条目时返回 false
  private func start(session: Int, entries: [[String: Any]]) -> Bool {
    guard let vc = controller, let window = vc.view.window, !entries.isEmpty,
      NSEvent.pressedMouseButtons & 1 != 0
    else { return false }
    let location = window.mouseLocationOutsideOfEventStream
    let event = currentDragEvent(window: window, location: location)
    let origin = vc.view.convert(location, from: nil)

    var items: [NSDraggingItem] = []
    for (i, e) in entries.enumerated() {
      let name = e["path"] as? String ?? "file"
      let isDir = e["isDir"] as? Bool ?? false
      let type = isDir ? UTType.folder : (UTType(filenameExtension: (name as NSString).pathExtension) ?? .data)
      let provider = NSFilePromiseProvider(fileType: type.identifier, delegate: self)
      provider.userInfo = PromiseInfo(session: session, index: i, name: name)
      let item = NSDraggingItem(pasteboardWriter: provider)
      // 拖动图像为系统文件图标，多个文件错开叠放，左上角对齐指针
      let offset = CGFloat(min(i, 4)) * 4
      let frame = NSRect(x: origin.x + offset, y: origin.y - 32 - offset, width: 32, height: 32)
      item.setDraggingFrame(frame, contents: NSWorkspace.shared.icon(for: type))
      items.append(item)
    }
    activeSession = session
    let dragSession = vc.view.beginDraggingSession(with: items, event: event, source: self)
    dragSession.animatesToStartingPositionsOnCancelOrFail = false
    // 系统拖动接管鼠标后 Flutter 收不到松开事件，补发一个，结束应用内的拖动手势
    if let up = NSEvent.mouseEvent(
      with: .leftMouseUp, location: location, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
      windowNumber: window.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 0)
    {
      vc.mouseUp(with: up)
    }
    return true
  }

  /// 开始拖动所需的鼠标事件：优先用当前的拖动事件，否则按指针位置构造
  private func currentDragEvent(window: NSWindow, location: NSPoint) -> NSEvent {
    if let e = NSApp.currentEvent, e.type == .leftMouseDragged || e.type == .leftMouseDown {
      return e
    }
    return NSEvent.mouseEvent(
      with: .leftMouseDragged, location: location, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
      windowNumber: window.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 1)!
  }

  // MARK: NSDraggingSource

  /// 只允许拖到其他应用（Finder）；拖回本窗口不处理，避免与应用内拖放、desktop_drop 冲突
  func draggingSession(_ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext)
    -> NSDragOperation
  {
    context == .outsideApplication ? .copy : []
  }

  func draggingSession(_ session: NSDraggingSession, endedAt screenPoint: NSPoint, operation: NSDragOperation) {
    channel?.invokeMethod("ended", arguments: ["session": activeSession])
  }

  // MARK: NSFilePromiseProviderDelegate

  func filePromiseProvider(_ provider: NSFilePromiseProvider, fileNameForType fileType: String) -> String {
    (provider.userInfo as? PromiseInfo)?.name ?? "file"
  }

  /// Finder 放下后回调：请求 Dart 下载到 url，完成或失败后通知系统
  func filePromiseProvider(
    _ provider: NSFilePromiseProvider, writePromiseTo url: URL, completionHandler: @escaping (Error?) -> Void
  ) {
    guard let info = provider.userInfo as? PromiseInfo, let ch = channel else {
      completionHandler(NSError(domain: "remlark.file_drag", code: 1))
      return
    }
    ch.invokeMethod("write", arguments: ["session": info.session, "index": info.index, "path": url.path]) { r in
      if let err = r as? FlutterError {
        completionHandler(
          NSError(domain: "remlark.file_drag", code: 2, userInfo: [NSLocalizedDescriptionKey: err.message ?? err.code]))
      } else {
        completionHandler(nil)
      }
    }
  }

  /// 写入回调在主线程执行：Flutter 通道只能在主线程调用
  func operationQueue(for filePromiseProvider: NSFilePromiseProvider) -> OperationQueue {
    .main
  }
}
