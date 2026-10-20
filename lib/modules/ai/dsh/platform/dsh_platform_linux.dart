import 'dart:ffi';

import 'dsh_platform_posix.dart';

/// Linux：`node-v<版本>-linux-<x64|arm64>.tar.gz`
class LinuxDshPlatform extends PosixDshPlatform {
  LinuxDshPlatform(this.abi);

  final Abi abi;

  @override
  String? nodeAsset(String version) {
    final arch = switch (abi) {
      Abi.linuxX64 => 'x64',
      Abi.linuxArm64 => 'arm64',
      _ => null,
    };
    return arch == null ? null : 'node-v$version-linux-$arch.tar.gz';
  }
}
