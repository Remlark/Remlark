import 'dart:ffi';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:remlark/utils/platform_utils.dart';

/// 定位真正的 Dart 可执行文件，避免 Windows 上直接启动 dart.bat 失败。
String dartExecutable() {
  final dart = PlatformUtils.which('dart');
  if (dart == null) throw StateError('Dart SDK not found in PATH');
  if (!dart.toLowerCase().endsWith('.bat')) return dart;
  final executable = p.join(p.dirname(dart), 'cache', 'dart-sdk', 'bin', 'dart.exe');
  if (!File(executable).existsSync()) throw StateError('Dart executable not found: $executable');
  return executable;
}

/// 当前平台原生库的构建目录名（与 hook/build.dart、native/*/scripts 的输出目录一致）：
/// macos-x86_64 / macos-arm64、linux-x86_64 / linux-aarch64、windows-x86_64 / windows-arm64。
/// 按当前 Dart 进程的 ABI 判断（与构建钩子打包时选择的架构相同），不支持时返回 null
String? nativeBuildName() => switch (Abi.current()) {
  Abi.macosX64 => 'macos-x86_64',
  Abi.macosArm64 => 'macos-arm64',
  Abi.linuxX64 => 'linux-x86_64',
  Abi.linuxArm64 => 'linux-aarch64',
  Abi.windowsX64 => 'windows-x86_64',
  Abi.windowsArm64 => 'windows-arm64',
  _ => null,
};

/// 当前平台原生库构建目录下的文件，例如 `nativeBuildFile('clip_test_server')`
File nativeBuildFile(String relative) => File(p.join('build', 'native', nativeBuildName() ?? 'unsupported', relative));

/// 系统 tar：Windows 使用 System32 自带的 bsdtar（PATH 里可能是 Git 的 tar，不识别 C:\ 路径），其余平台用 PATH 中的 tar
String systemTar() {
  if (!Platform.isWindows) return 'tar';
  final systemRoot = Platform.environment['SystemRoot'] ?? r'C:\Windows';
  return p.join(systemRoot, 'System32', 'tar.exe');
}

/// 当前登录用户名（macOS / Linux 为 USER，Windows 为 USERNAME）
String? currentUserName() => Platform.environment['USER'] ?? Platform.environment['USERNAME'];
