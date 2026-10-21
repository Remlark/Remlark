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
    final w = kDefaultWindowSize.width.toInt(),
        h = kDefaultWindowSize.height.toInt();
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

  test('FreeRDP 使用依赖自身版本，避免应用 Release 标签改变库名', () {
    for (final name in ['build.sh', 'build.ps1', 'build_test_server.sh']) {
      expect(
        File('native/rdp/scripts/$name').readAsStringSync(),
        contains('-DUSE_VERSION_FROM_GIT_TAG=OFF'),
      );
    }
    expect(
      File('native/rdp/scripts/build.ps1').readAsStringSync(),
      contains(r'$env:SystemRoot\System32\tar.exe'),
    );
  });

  test('原生库构建钩子与构建脚本覆盖三个平台及 x64 / arm64', () {
    final hook = src('hook/build.dart');
    for (final os in ['OS.macOS', 'OS.linux', 'OS.windows']) {
      expect(hook, contains(os));
    }
    for (final lib in ['native/rdp', 'native/ssh_crypto']) {
      expect(
        File('$lib/scripts/build.sh').existsSync(),
        isTrue,
        reason: '$lib 缺少 macOS / Linux 构建脚本',
      );
      expect(
        File('$lib/scripts/build.ps1').existsSync(),
        isTrue,
        reason: '$lib 缺少 Windows 构建脚本',
      );
      // Windows 脚本支持 x64 与 arm64，输出目录与构建钩子的 windows-x86_64 / windows-arm64 一致
      final ps = src('$lib/scripts/build.ps1');
      // Windows PowerShell 5.1 按系统代码页读取无 BOM 脚本，中文标点可能破坏字符串解析。
      expect(File('$lib/scripts/build.ps1').readAsBytesSync().take(3), [
        0xef,
        0xbb,
        0xbf,
      ]);
      expect(
        ps,
        contains('[ValidateSet("x86_64", "arm64")]'),
        reason: '$lib/scripts/build.ps1',
      );
      expect(
        ps,
        contains(r'build\native\windows-$Arch'),
        reason: '$lib/scripts/build.ps1',
      );
      expect(ps, contains('Invoke-BuildCommand cmake'));
      expect(ps, contains('-DCMAKE_C_COMPILER=cl'));
    }
    // 构建钩子中 Windows / macOS 的 arm64 目录名为 arm64，Linux 为 aarch64
    expect(
      hook,
      contains("Architecture.arm64 => os == OS.linux ? 'aarch64' : 'arm64'"),
    );
    // macOS / Linux 测试服务端必须从同一前缀查找 OpenSSL 和 pkg-config 元数据。
    final testServer = src('native/rdp/scripts/build_test_server.sh');
    expect(testServer, contains(r'-DCMAKE_PREFIX_PATH="$PREFIX"'));
    expect(testServer, contains('-DWITH_SYSTEMD=OFF'));
    final makefile = src('Makefile');
    expect(src('native/rdp/scripts/build.ps1'), contains('zlibstatic.lib'));
    expect(
      src('native/rdp/scripts/build.ps1'),
      contains(r'perl Configure $OpenSslTarget /FS'),
    );
    expect(src('native/rdp/scripts/build.ps1'), contains('-DWITH_CCACHE=OFF'));
    expect(src('native/rdp/CMakeLists.txt'), contains('zlibstatic.lib'));
    final rdpBuild = src('native/rdp/CMakeLists.txt');
    expect(rdpBuild, contains('WIN32_LEAN_AND_MEAN NOMINMAX FREERDP_EXPORTS'));
    expect(rdpBuild, contains(r'${REMLARK_DEPS_PREFIX}/remdesk-common.lib'));
    expect(rdpBuild, contains('credui'));
    final clipboard = src('native/rdp/src/rmk_clipboard.c');
    expect(clipboard, contains('FD_ATTRIBUTES | FD_FILESIZE | FD_PROGRESSUI'));
    expect(
      clipboard.indexOf('#include "rmk_internal.h"'),
      lessThan(clipboard.indexOf('#include <winpr/shell.h>')),
    );
    expect(src('windows/CMakeLists.txt'), contains('/utf-8'));
    for (final lib in ['rdp', 'ssh_crypto']) {
      expect(src('native/$lib/CMakeLists.txt'), contains('/utf-8'));
    }
    for (final target in ['mac:', 'linux:', 'windows:', 'run:']) {
      expect(makefile, contains(target));
    }
  });

  test('Windows PowerShell 可以解析两个原生库构建脚本', () async {
    if (!Platform.isWindows) return; // 其他平台的原生构建使用 build.sh。
    for (final lib in ['rdp', 'ssh_crypto']) {
      final result = await Process.run('powershell', [
        '-NoProfile',
        '-Command',
        '\$tokens = \$null; \$errors = \$null; '
            '[System.Management.Automation.Language.Parser]::ParseFile('
            "'native/$lib/scripts/build.ps1', [ref]\$tokens, [ref]\$errors) | Out-Null; "
            'if (\$errors.Count) { \$errors | Out-String | Write-Output; exit 1 }',
      ]);
      expect(result.exitCode, 0, reason: '${result.stdout}\n${result.stderr}');
    }
  });

  test('NMake 不继承 GNU Make 参数，执行后恢复环境', () async {
    if (!Platform.isWindows) return;
    final root = Directory.systemTemp.createTempSync('remlark nmake ');
    addTearDown(() => root.deleteSync(recursive: true));
    final fake = File('${root.path}/nmake.cmd')
      ..writeAsStringSync(
        '@echo off\r\necho MAKEFLAGS=[%MAKEFLAGS%]\r\nexit /b 0\r\n',
      );
    final result = await Process.run(
      'powershell',
      [
        '-NoProfile',
        // 只放行当前测试进程中的项目脚本，保持系统全局执行策略不变。
        '-ExecutionPolicy',
        'Bypass',
        '-Command',
        ". './native/utils/windows_build.ps1'; "
            r"$env:MAKEFLAGS = '-- bad=value'; "
            'Invoke-BuildCommand \$env:RMK_NMAKE; '
            r"if ($env:MAKEFLAGS -ne '-- bad=value') { exit 2 }",
      ],
      environment: {'RMK_NMAKE': fake.path},
    );
    expect(result.exitCode, 0, reason: '${result.stdout}${result.stderr}');
    expect(result.stdout, contains('MAKEFLAGS=[]'));
  });

  test('原生构建遇到外部命令失败时立即报错', () async {
    if (Platform.isWindows) {
      final forwarded = await Process.run('powershell', [
        '-NoProfile',
        '-ExecutionPolicy',
        'Bypass',
        '-Command',
        ". './native/utils/windows_build.ps1'; Invoke-BuildCommand cmd /c echo -C preserved",
      ]);
      expect(forwarded.exitCode, 0, reason: '${forwarded.stderr}');
      expect(forwarded.stdout, contains('-C preserved'));
      final result = await Process.run('powershell', [
        '-NoProfile',
        '-ExecutionPolicy',
        'Bypass',
        '-Command',
        ". './native/utils/windows_build.ps1'; Invoke-BuildCommand cmd /c exit 7; exit 0",
      ]);
      expect(result.exitCode, isNot(0));
      expect(
        '${result.stdout}${result.stderr}',
        contains('Build command failed (7)'),
      );
    } else {
      // POSIX 脚本已有严格错误检查，两个库必须保持一致。
      for (final lib in ['rdp', 'ssh_crypto']) {
        expect(
          src('native/$lib/scripts/build.sh'),
          contains('set -euo pipefail'),
        );
      }
    }
  });
}
