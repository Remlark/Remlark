import 'dart:ffi';
import 'dart:io';

import 'codex_platform_linux.dart';
import 'codex_platform_macos.dart';
import 'codex_platform_windows.dart';

/// Codex 运行环境中与平台相关的部分：发布包名称与可执行文件名。
/// 每个平台各自实现，修改时三个平台需要一起改。
abstract class CodexPlatform {
  /// 当前平台的实现
  factory CodexPlatform.current() {
    if (Platform.isMacOS) return MacosCodexPlatform(Abi.current());
    if (Platform.isWindows) return WindowsCodexPlatform(Abi.current());
    return LinuxCodexPlatform(Abi.current());
  }

  /// GitHub Releases 中当前平台的完整运行包名称（含主程序、执行工具与资源），
  /// 例如 `codex-package-aarch64-apple-darwin.tar.gz`；当前架构不支持时返回 null
  String? get releaseAsset;

  /// 主程序文件名
  String get executableName;

  /// 执行工具文件名（必须与主程序同目录）
  String get codeModeHostName;
}

/// 发布包使用的 Rust 架构名：x86_64 / aarch64，不支持的架构返回 null
String? codexRustArch(Abi abi) => switch (abi) {
  Abi.macosArm64 || Abi.linuxArm64 || Abi.windowsArm64 => 'aarch64',
  Abi.macosX64 || Abi.linuxX64 || Abi.windowsX64 => 'x86_64',
  _ => null,
};
