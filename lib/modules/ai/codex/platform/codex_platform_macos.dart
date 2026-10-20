import 'dart:ffi';

import 'codex_platform.dart';

/// macOS：Apple Silicon 与 Intel 分别使用 aarch64 / x86_64 的 apple-darwin 包
class MacosCodexPlatform implements CodexPlatform {
  MacosCodexPlatform(this.abi);

  final Abi abi;

  @override
  String? get releaseAsset {
    final arch = codexRustArch(abi);
    return arch == null ? null : 'codex-package-$arch-apple-darwin.tar.gz';
  }

  @override
  String get executableName => 'codex';

  @override
  String get codeModeHostName => 'codex-code-mode-host';
}
