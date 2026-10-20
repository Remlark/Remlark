import 'dart:io';

import 'package:path/path.dart' as p;

import 'archive_extractor.dart';

/// Windows：优先用系统自带的 bsdtar（Windows 10 1803+，支持 zip 与 tar.gz；PATH 里可能是不支持 zip 的 Git tar），
/// 不存在时 zip 退回 PowerShell Expand-Archive（不支持 tar.gz）
class WindowsArchiveExtractor implements ArchiveExtractor {
  @override
  Future<void> extract(File archive, Directory dest) async {
    final systemRoot = Platform.environment['SystemRoot'] ?? r'C:\Windows';
    final tar = p.join(systemRoot, 'System32', 'tar.exe');
    final ProcessResult r;
    if (File(tar).existsSync()) {
      r = await Process.run(tar, ['-xf', archive.path, '-C', dest.path]);
    } else {
      r = await Process.run(
        'powershell',
        ['-NoProfile', '-Command', 'Expand-Archive -LiteralPath \$env:RMK_SRC -DestinationPath \$env:RMK_DEST -Force'],
        environment: {'RMK_SRC': archive.path, 'RMK_DEST': dest.path},
      );
    }
    if (r.exitCode != 0) throw ProcessException('tar', const [], '${r.stderr}'.trim(), r.exitCode);
  }
}
