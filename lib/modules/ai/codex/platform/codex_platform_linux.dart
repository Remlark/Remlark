import 'dart:ffi';

import 'codex_platform.dart';

/// Linux：使用静态链接的 musl 包，不依赖发行版的 glibc 版本
class LinuxCodexPlatform implements CodexPlatform {
  LinuxCodexPlatform(this.abi);

  final Abi abi;

  @override
  String? get releaseAsset {
    final arch = codexRustArch(abi);
    return arch == null ? null : 'codex-package-$arch-unknown-linux-musl.tar.gz';
  }

  @override
  String get executableName => 'codex';

  @override
  String get codeModeHostName => 'codex-code-mode-host';
}
