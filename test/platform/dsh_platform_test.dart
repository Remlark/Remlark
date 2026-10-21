import 'dart:ffi';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:remlark/modules/ai/dsh/dsh_environment.dart';
import 'package:remlark/modules/ai/dsh/platform/dsh_platform.dart';
import 'package:remlark/modules/ai/dsh/platform/dsh_platform_linux.dart';
import 'package:remlark/modules/ai/dsh/platform/dsh_platform_macos.dart';
import 'package:remlark/modules/ai/dsh/platform/dsh_platform_windows.dart';

/// 多平台测试 P-02：dsh 私有 Node.js 安装包名称、目录布局与 PATH 拼接（见 docs/multi-platform-testing.md）
void main() {
  test('dsh 平台实现：Node.js 安装包名称', () {
    expect(MacosDshPlatform(Abi.macosArm64).nodeAsset('24.11.1'), 'node-v24.11.1-darwin-arm64.tar.gz');
    expect(MacosDshPlatform(Abi.macosX64).nodeAsset('24.11.1'), 'node-v24.11.1-darwin-x64.tar.gz');
    expect(LinuxDshPlatform(Abi.linuxX64).nodeAsset('24.11.1'), 'node-v24.11.1-linux-x64.tar.gz');
    expect(LinuxDshPlatform(Abi.linuxArm64).nodeAsset('24.11.1'), 'node-v24.11.1-linux-arm64.tar.gz');
    expect(WindowsDshPlatform(Abi.windowsX64).nodeAsset('24.11.1'), 'node-v24.11.1-win-x64.zip');
    expect(WindowsDshPlatform(Abi.windowsArm64).nodeAsset('24.11.1'), 'node-v24.11.1-win-arm64.zip');
    // ABI 与平台实现不匹配或架构不支持时返回 null
    expect(LinuxDshPlatform(Abi.macosArm64).nodeAsset('24.11.1'), isNull);
    expect(WindowsDshPlatform(Abi.windowsIA32).nodeAsset('24.11.1'), isNull);
  });

  test('dsh 平台实现：node / npm 目录布局与 PATH 分隔符', () {
    const dir = 'node';
    for (final posix in [MacosDshPlatform(Abi.macosArm64), LinuxDshPlatform(Abi.linuxX64)]) {
      expect(posix.nodeExecutable(dir), p.join(dir, 'bin', 'node'));
      expect(posix.npmCli(dir), p.join(dir, 'lib', 'node_modules', 'npm', 'bin', 'npm-cli.js'));
      expect(posix.nodeBinDir(dir), p.join(dir, 'bin'));
      expect(posix.pathSeparator, ':');
    }
    final win = WindowsDshPlatform(Abi.windowsX64);
    expect(win.nodeExecutable(dir), p.join(dir, 'node.exe'));
    expect(win.npmCli(dir), p.join(dir, 'node_modules', 'npm', 'bin', 'npm-cli.js'));
    expect(win.nodeBinDir(dir), dir);
    expect(win.pathSeparator, ';');
  });

  test('dsh 平台实现：current() 与当前系统一致；子进程 PATH 以私有 node 目录开头（Windows 的 Path 键大小写不敏感）', () {
    final current = DshPlatform.current();
    if (Platform.isMacOS) expect(current, isA<MacosDshPlatform>());
    if (Platform.isWindows) expect(current, isA<WindowsDshPlatform>());
    if (Platform.isLinux) expect(current, isA<LinuxDshPlatform>());
    expect(current.nodeAsset('24.11.1'), isNotNull);

    final env = DshEnvironment(p.join(Directory.systemTemp.path, 'rmk-dsh'), current);
    final vars = env.processEnvironment(apiKey: 'k');
    // 只能有一个 PATH 键（Windows 下为 Path），不能另外新增一个 PATH
    final keys = vars.keys.where((k) => k.toUpperCase() == 'PATH').toList();
    expect(keys, hasLength(1));
    final parts = vars[keys.single]!.split(current.pathSeparator);
    expect(parts.first, current.nodeBinDir(env.nodeDir));
    expect(vars['DSH_HOME'], env.homeDir);
    expect(vars['DEEPSEEK_API_KEY'], 'k');
  });
}
