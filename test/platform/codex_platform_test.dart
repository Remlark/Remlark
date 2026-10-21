import 'dart:ffi';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:remlark/modules/ai/codex/platform/codex_platform.dart';
import 'package:remlark/modules/ai/codex/platform/codex_platform_linux.dart';
import 'package:remlark/modules/ai/codex/platform/codex_platform_macos.dart';
import 'package:remlark/modules/ai/codex/platform/codex_platform_windows.dart';

/// 多平台测试 P-01：Codex 发布包名称与可执行文件名（见 docs/multi-platform-testing.md）
void main() {
  test('Codex 平台实现：三个平台、两种架构的发布包名称与可执行文件名', () {
    expect(MacosCodexPlatform(Abi.macosArm64).releaseAsset, 'codex-package-aarch64-apple-darwin.tar.gz');
    expect(MacosCodexPlatform(Abi.macosX64).releaseAsset, 'codex-package-x86_64-apple-darwin.tar.gz');
    expect(LinuxCodexPlatform(Abi.linuxX64).releaseAsset, 'codex-package-x86_64-unknown-linux-musl.tar.gz');
    expect(LinuxCodexPlatform(Abi.linuxArm64).releaseAsset, 'codex-package-aarch64-unknown-linux-musl.tar.gz');
    expect(WindowsCodexPlatform(Abi.windowsX64).releaseAsset, 'codex-package-x86_64-pc-windows-msvc.tar.gz');
    expect(WindowsCodexPlatform(Abi.windowsArm64).releaseAsset, 'codex-package-aarch64-pc-windows-msvc.tar.gz');

    // 不支持的架构返回 null（界面提示“当前平台不支持”）
    expect(LinuxCodexPlatform(Abi.linuxIA32).releaseAsset, isNull);
    expect(WindowsCodexPlatform(Abi.windowsIA32).releaseAsset, isNull);

    // Windows 可执行文件带 .exe，其余平台不带
    expect(MacosCodexPlatform(Abi.macosArm64).executableName, 'codex');
    expect(LinuxCodexPlatform(Abi.linuxX64).codeModeHostName, 'codex-code-mode-host');
    expect(WindowsCodexPlatform(Abi.windowsX64).executableName, 'codex.exe');
    expect(WindowsCodexPlatform(Abi.windowsX64).codeModeHostName, 'codex-code-mode-host.exe');
  });

  test('Codex 平台实现：current() 选择与当前系统一致的实现，且当前架构有发布包', () {
    final current = CodexPlatform.current();
    if (Platform.isMacOS) expect(current, isA<MacosCodexPlatform>());
    if (Platform.isWindows) expect(current, isA<WindowsCodexPlatform>());
    if (Platform.isLinux) expect(current, isA<LinuxCodexPlatform>());
    expect(current.releaseAsset, isNotNull);
  });
}
