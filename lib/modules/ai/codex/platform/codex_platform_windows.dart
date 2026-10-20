import 'dart:ffi';

import 'codex_platform.dart';

/// Windows：msvc 包，可执行文件带 .exe 后缀
class WindowsCodexPlatform implements CodexPlatform {
  WindowsCodexPlatform(this.abi);

  final Abi abi;

  @override
  String? get releaseAsset {
    final arch = codexRustArch(abi);
    return arch == null ? null : 'codex-package-$arch-pc-windows-msvc.tar.gz';
  }

  @override
  String get executableName => 'codex.exe';

  @override
  String get codeModeHostName => 'codex-code-mode-host.exe';
}
