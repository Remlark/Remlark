import Cocoa

/// 独立原生测试，不显示窗口或 Dock 项：验证真实 NSApplication 图标更新与缺失资源回退。
@main
struct AppIconProbe {
  /// 以正常错误码报告失败，避免测试失败生成系统崩溃弹窗。
  static func require(_ condition: @autoclosure () -> Bool, _ message: String) {
    guard condition() else {
      FileHandle.standardError.write(Data("\(message)\n".utf8))
      exit(1)
    }
  }

  /// 将图标绘制为相同的 RGBA 位图，排除 TIFF 元数据与表示顺序差异。
  static func pixels(_ image: NSImage, representationWidth: Int? = nil, output: URL? = nil) -> [UInt8] {
    let size = 256
    let context = CGContext(
      data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: size * 4,
      space: CGColorSpaceCreateDeviceRGB(),
      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    )!
    var rect = CGRect(x: 0, y: 0, width: size, height: size)
    // 不同 macOS 版本采用 512 或 1024 像素，按系统实际密度选择同一份源表示。
    let bitmap = image.representations.compactMap { $0 as? NSBitmapImageRep }.filter {
      representationWidth == nil || $0.pixelsWide == representationWidth
    }.max {
      $0.pixelsWide * $0.pixelsHigh < $1.pixelsWide * $1.pixelsHigh
    }
    let cgImage = bitmap?.cgImage ?? image.cgImage(
      forProposedRect: &rect, context: NSGraphicsContext(cgContext: context, flipped: false), hints: nil
    )!
    context.draw(cgImage, in: CGRect(x: 0, y: 0, width: size, height: size))
    if let output = output {
      try! NSBitmapImageRep(cgImage: context.makeImage()!).representation(using: .png, properties: [:])!.write(to: output)
    }
    return Array(UnsafeBufferPointer(start: context.data!.assumingMemoryBound(to: UInt8.self), count: size * size * 4))
  }

  /// 先设置不同的图标，再调用应用的真实实现，确认成功更新且失败时不覆盖。
  static func main() {
    let app = NSApplication.shared
    app.setActivationPolicy(.prohibited)
    app.finishLaunching()
    let bundle = Bundle(path: CommandLine.arguments[1])!
    let missing = Bundle(path: CommandLine.arguments[2])!
    let expected = NSImage(contentsOf: bundle.url(forResource: "AppIcon", withExtension: "icns")!)!
    app.applicationIconImage = NSImage(named: NSImage.cautionName)!
    require(pixels(app.applicationIconImage) != pixels(expected), "测试前应为其他图标")
    require(ApplicationIcon.refresh(in: app, bundle: bundle), "应能读取当前应用包图标")
    let output = URL(fileURLWithPath: CommandLine.arguments[3])
    let actualPixels = pixels(app.applicationIconImage, output: output.appendingPathComponent("actual.png"))
    let density = app.applicationIconImage.representations.map { $0.pixelsWide }.max()!
    let expectedPixels = pixels(expected, representationWidth: density, output: output.appendingPathComponent("expected.png"))
    let maxDifference = zip(actualPixels, expectedPixels).map { abs(Int($0) - Int($1)) }.max()!
    FileHandle.standardError.write(Data("Icon comparison: actual=\(app.applicationIconImage.representations.map { $0.pixelsWide }), expected=\(expected.representations.map { $0.pixelsWide }), maxDifference=\(maxDifference)\n".utf8))
    // 系统将多分辨率图标栅格化，允许色彩转换的一档舍入误差。
    require(maxDifference <= 1, "Dock 图标必须与当前包一致")
    require(!ApplicationIcon.refresh(in: app, bundle: missing), "缺失资源应返回失败")
    require(pixels(app.applicationIconImage) == actualPixels, "缺失资源不得覆盖正确图标")
    print("Dock icon refresh and fallback passed")
  }
}
