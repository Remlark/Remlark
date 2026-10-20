import 'dart:ffi';

import 'dsh_platform_posix.dart';

/// macOS：`node-v<版本>-darwin-<arm64|x64>.tar.gz`
class MacosDshPlatform extends PosixDshPlatform {
  MacosDshPlatform(this.abi);

  final Abi abi;

  @override
  String? nodeAsset(String version) {
    final arch = switch (abi) {
      Abi.macosArm64 => 'arm64',
      Abi.macosX64 => 'x64',
      _ => null,
    };
    return arch == null ? null : 'node-v$version-darwin-$arch.tar.gz';
  }
}
