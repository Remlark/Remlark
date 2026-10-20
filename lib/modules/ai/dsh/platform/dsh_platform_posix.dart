import 'package:path/path.dart' as p;

import 'dsh_platform.dart';

/// macOS 与 Linux 共用的部分：bin/node 目录布局
abstract class PosixDshPlatform implements DshPlatform {
  @override
  String nodeExecutable(String nodeDir) => p.join(nodeDir, 'bin', 'node');

  @override
  String npmCli(String nodeDir) => p.join(nodeDir, 'lib', 'node_modules', 'npm', 'bin', 'npm-cli.js');

  @override
  String nodeBinDir(String nodeDir) => p.join(nodeDir, 'bin');

  @override
  String get pathSeparator => ':';
}
