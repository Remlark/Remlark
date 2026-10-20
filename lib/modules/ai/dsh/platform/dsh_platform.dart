import 'dart:ffi';
import 'dart:io';

import 'dsh_platform_linux.dart';
import 'dsh_platform_macos.dart';
import 'dsh_platform_windows.dart';

/// dsh 运行环境中与平台相关的部分：Node.js 安装包名称与目录布局（解压见 ArchiveExtractor）。
/// 每个平台各自实现，修改时三个平台需要一起改。
abstract class DshPlatform {
  /// 当前平台的实现
  factory DshPlatform.current() {
    if (Platform.isMacOS) return MacosDshPlatform(Abi.current());
    if (Platform.isWindows) return WindowsDshPlatform(Abi.current());
    return LinuxDshPlatform(Abi.current());
  }

  /// Node.js 官方安装包文件名，例如 `node-v24.11.1-darwin-arm64.tar.gz`；当前架构不支持时返回 null
  String? nodeAsset(String version);

  /// 解压后 Node.js 目录中的 node 可执行文件
  String nodeExecutable(String nodeDir);

  /// 解压后 Node.js 目录中 npm 的入口脚本（直接用 node 运行，不依赖 PATH 与符号链接）
  String npmCli(String nodeDir);

  /// 需要加入 PATH 的目录（dsh 及其安装脚本会再启动 node）
  String nodeBinDir(String nodeDir);

  /// PATH 分隔符
  String get pathSeparator;

}
