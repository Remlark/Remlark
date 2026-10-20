import 'dart:ffi';

import 'package:path/path.dart' as p;

import 'dsh_platform.dart';

/// Windows：`node-v<版本>-win-<x64|arm64>.zip`，node.exe 位于根目录
class WindowsDshPlatform implements DshPlatform {
  WindowsDshPlatform(this.abi);

  final Abi abi;

  @override
  String? nodeAsset(String version) {
    final arch = switch (abi) {
      Abi.windowsX64 => 'x64',
      Abi.windowsArm64 => 'arm64',
      _ => null,
    };
    return arch == null ? null : 'node-v$version-win-$arch.zip';
  }

  @override
  String nodeExecutable(String nodeDir) => p.join(nodeDir, 'node.exe');

  @override
  String npmCli(String nodeDir) => p.join(nodeDir, 'node_modules', 'npm', 'bin', 'npm-cli.js');

  @override
  String nodeBinDir(String nodeDir) => nodeDir;

  @override
  String get pathSeparator => ';';
}
