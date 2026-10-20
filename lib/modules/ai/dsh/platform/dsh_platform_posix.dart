import 'dart:io';

import 'package:path/path.dart' as p;

import 'dsh_platform.dart';

/// macOS 与 Linux 共用的部分：tar.gz 安装包、bin/node 目录布局、系统 tar 解压
abstract class PosixDshPlatform implements DshPlatform {
  @override
  String nodeExecutable(String nodeDir) => p.join(nodeDir, 'bin', 'node');

  @override
  String npmCli(String nodeDir) => p.join(nodeDir, 'lib', 'node_modules', 'npm', 'bin', 'npm-cli.js');

  @override
  String nodeBinDir(String nodeDir) => p.join(nodeDir, 'bin');

  @override
  String get pathSeparator => ':';

  /// 用系统 tar 解压（安装包含符号链接，系统 tar 能正确还原）
  @override
  Future<void> extract(File archive, Directory dest) async {
    final r = await Process.run('tar', ['-xzf', archive.path, '-C', dest.path]);
    if (r.exitCode != 0) throw ProcessException('tar', const [], '${r.stderr}'.trim(), r.exitCode);
  }
}
