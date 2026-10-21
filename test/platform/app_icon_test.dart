import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';

/// 多平台测试 P-14：品牌图标资源、系统关联及 macOS 原生 Dock 图标刷新。
void main() {
  test('三个平台使用同一品牌图标并配置正确的系统入口', () async {
    final brand = File('assets/branding/app_icon.png').readAsBytesSync();
    expect(
      File('macos/Runner/Assets.xcassets/AppIcon.appiconset/app_icon_256.png')
          .readAsBytesSync(),
      brand,
    );
    expect(
      File('linux/packaging/icons/hicolor/256x256/apps/com.remlark.remlark.png')
          .readAsBytesSync(),
      brand,
    );
    final ico = File('windows/runner/resources/app_icon.ico').readAsBytesSync();
    final header = ByteData.sublistView(ico);
    expect(header.getUint16(2, Endian.little), 1);
    expect(header.getUint16(4, Endian.little), 7);
    // ICO 最大帧为 PNG，解码后逐像素核对，防止 Windows 仍残留其他品牌图标。
    final entry = 6 + 6 * 16;
    expect(ico[entry], 0); // ICO 中 0 表示 256 像素。
    final length = header.getUint32(entry + 8, Endian.little);
    final offset = header.getUint32(entry + 12, Endian.little);
    final brandCodec = await ui.instantiateImageCodec(brand);
    final icoCodec = await ui.instantiateImageCodec(
      ico.sublist(offset, offset + length),
    );
    final brandFrame = await brandCodec.getNextFrame();
    final icoFrame = await icoCodec.getNextFrame();
    expect(
      (await icoFrame.image.toByteData())!.buffer.asUint8List(),
      (await brandFrame.image.toByteData())!.buffer.asUint8List(),
    );
    brandFrame.image.dispose();
    icoFrame.image.dispose();
    brandCodec.dispose();
    icoCodec.dispose();
    expect(
      File('windows/runner/Runner.rc').readAsStringSync(),
      contains('IDI_APP_ICON'),
    );
    expect(
      File('windows/runner/win32_window.cpp').readAsStringSync(),
      contains('LoadIcon('),
    );
    expect(
      File('linux/packaging/com.remlark.remlark.desktop').readAsStringSync(),
      contains('Icon=com.remlark.remlark'),
    );
    expect(
      File('linux/runner/my_application.cc').readAsStringSync(),
      contains('APPLICATION_ID'),
    );
    expect(
      File('linux/CMakeLists.txt').readAsStringSync(),
      contains('com.remlark.remlark'),
    );
    final delegate = File('macos/Runner/AppDelegate.swift').readAsStringSync();
    expect(delegate, contains('applicationDidFinishLaunching'));
    expect(delegate, contains('ApplicationIcon.refresh()'));
    final project = File('macos/Runner.xcodeproj/project.pbxproj')
        .readAsStringSync();
    expect(project, contains('ApplicationIcon.swift in Sources'));
  });

  test('macOS 原生刷新实际更新应用图标，缺失资源时保留原图标', () async {
    if (!Platform.isMacOS) return; // Windows / Linux 的资源及系统关联由上面的测试覆盖。
    final root = Directory.systemTemp.createTempSync('rmk icon 中文 ');
    addTearDown(() => root.deleteSync(recursive: true));
    final iconset = Directory('${root.path}/brand.iconset')..createSync();
    final catalog = 'macos/Runner/Assets.xcassets/AppIcon.appiconset';
    final entries =
        jsonDecode(File('$catalog/Contents.json').readAsStringSync())['images']
            as List;
    for (final entry in entries) {
      final size = (entry['size'] as String).split('x').first;
      final scale = entry['scale'] == '2x' ? '@2x' : '';
      File('$catalog/${entry['filename']}')
          .copySync('${iconset.path}/icon_${size}x$size$scale.png');
    }
    final resources = Directory('${root.path}/Current.app/Contents/Resources')
      ..createSync(recursive: true);
    final missing = Directory('${root.path}/Missing.app/Contents')
      ..createSync(recursive: true);
    // 独立夹具不启动真实应用、不访问用户数据，也不依赖已经构建的 .app。
    for (final contents in [resources.parent, missing]) {
      File('${contents.path}/Info.plist')
          .writeAsStringSync('''<?xml version="1.0" encoding="UTF-8"?>
<plist version="1.0"><dict>
<key>CFBundleIdentifier</key><string>com.remlark.icon-test.${contents.parent.path.contains('Missing') ? 'missing' : 'current'}</string>
<key>CFBundlePackageType</key><string>APPL</string>
</dict></plist>''');
    }
    final convert = await Process.run('iconutil', [
      '-c',
      'icns',
      '-o',
      '${resources.path}/AppIcon.icns',
      iconset.path,
    ]);
    expect(convert.exitCode, 0, reason: '${convert.stderr}');
    final executable = '${root.path}/icon-probe';
    final compile = await Process.run('xcrun', [
      'swiftc',
      'macos/Runner/Branding/ApplicationIcon.swift',
      'test/platform/fixtures/app_icon_probe.swift',
      '-o',
      executable,
    ]);
    expect(compile.exitCode, 0, reason: '${compile.stderr}');
    final diagnostics = Directory('build/validation/dock-icon')
      ..createSync(recursive: true);
    final result = await Process.run(executable, [
      resources.parent.parent.path,
      missing.parent.path,
      diagnostics.absolute.path,
    ]);
    expect(result.exitCode, 0, reason: '${result.stdout}\n${result.stderr}');
    expect(result.stdout, contains('Dock icon refresh and fallback passed'));
  }, timeout: const Timeout(Duration(minutes: 3)));
}
