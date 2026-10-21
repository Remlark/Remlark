import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:remlark/app/window_config.dart';

/// 多平台测试 P-06：三个平台原生窗口代码与 lib/app/window_config.dart 的窗口尺寸一致，
/// 原生库构建钩子覆盖三个平台（见 docs/multi-platform-testing.md）。
/// 读取源码检查，不依赖当前平台，可在任意系统上运行
void main() {
  /// 读取源码文件
  String src(String path) => File(path).readAsStringSync();

  test('原生窗口默认尺寸与最小尺寸与 window_config.dart 一致', () {
    final w = kDefaultWindowSize.width.toInt(), h = kDefaultWindowSize.height.toInt();
    final mw = kMinWindowSize.width.toInt(), mh = kMinWindowSize.height.toInt();

    final mac = src('macos/Runner/MainFlutterWindow.swift');
    expect(mac, contains('NSSize(width: $mw, height: $mh)'));
    expect(mac, contains('NSSize(width: $w, height: $h)'));

    final linux = src('linux/runner/my_application.cc');
    expect(linux, contains('gtk_window_set_default_size(window, $w, $h)'));
    expect(linux, contains('min_width = $mw'));
    expect(linux, contains('min_height = $mh'));

    expect(src('windows/runner/main.cpp'), contains('Size size($w, $h)'));
    final winFrame = src('windows/runner/flutter_window.cpp');
    expect(winFrame, contains('MulDiv($mw, dpi, 96)'));
    expect(winFrame, contains('MulDiv($mh, dpi, 96)'));
  });

  test('原生库构建钩子与构建脚本覆盖三个平台及 x64 / arm64', () {
    final hook = src('hook/build.dart');
    for (final os in ['OS.macOS', 'OS.linux', 'OS.windows']) {
      expect(hook, contains(os));
    }
    for (final lib in ['native/rdp', 'native/ssh_crypto']) {
      expect(File('$lib/scripts/build.sh').existsSync(), isTrue, reason: '$lib 缺少 macOS / Linux 构建脚本');
      expect(File('$lib/scripts/build.ps1').existsSync(), isTrue, reason: '$lib 缺少 Windows 构建脚本');
      // Windows 脚本支持 x64 与 arm64，输出目录与构建钩子的 windows-x86_64 / windows-arm64 一致
      final ps = src('$lib/scripts/build.ps1');
      expect(ps, contains('[ValidateSet("x86_64", "arm64")]'), reason: '$lib/scripts/build.ps1');
      expect(ps, contains(r'build\native\windows-$Arch'), reason: '$lib/scripts/build.ps1');
    }
    // 构建钩子中 Windows / macOS 的 arm64 目录名为 arm64，Linux 为 aarch64
    expect(hook, contains("Architecture.arm64 => os == OS.linux ? 'aarch64' : 'arm64'"));
    final makefile = src('Makefile');
    for (final target in ['mac:', 'linux:', 'windows:', 'run:']) {
      expect(makefile, contains(target));
    }
  });
}
