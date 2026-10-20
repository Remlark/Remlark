import 'dart:ffi';
import 'dart:io';

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

  /// 优先用系统自带的 bsdtar（Windows 10 1803+，支持 zip；PATH 里可能是不支持 zip 的 Git tar），
  /// 不存在时退回 PowerShell Expand-Archive
  @override
  Future<void> extract(File archive, Directory dest) async {
    final systemRoot = Platform.environment['SystemRoot'] ?? r'C:\Windows';
    final tar = p.join(systemRoot, 'System32', 'tar.exe');
    final ProcessResult r;
    if (File(tar).existsSync()) {
      r = await Process.run(tar, ['-xf', archive.path, '-C', dest.path]);
    } else {
      r = await Process.run('powershell', [
        '-NoProfile',
        '-Command',
        'Expand-Archive -LiteralPath \$env:RMK_SRC -DestinationPath \$env:RMK_DEST -Force',
      ], environment: {'RMK_SRC': archive.path, 'RMK_DEST': dest.path});
    }
    if (r.exitCode != 0) throw ProcessException('tar', const [], '${r.stderr}'.trim(), r.exitCode);
  }
}
