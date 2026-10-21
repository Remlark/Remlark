import 'dart:io';

import 'package:path/path.dart' as p;

import 'archive_extractor.dart';

/// Windows：tar.gz 使用系统 bsdtar 并指定 UTF-8，zip 使用 PowerShell .NET 解压。
class WindowsArchiveExtractor implements ArchiveExtractor {
  @override
  Future<void> extract(File archive, Directory dest) async {
    final systemRoot = Platform.environment['SystemRoot'] ?? r'C:\Windows';
    final tar = p.join(systemRoot, 'System32', 'tar.exe');
    final ProcessResult r;
    // ZIP 使用 .NET，避开部分 Windows ARM64 系统 bsdtar 的 Unicode 文件名问题。
    final zip = archive.path.toLowerCase().endsWith('.zip');
    if (!zip && File(tar).existsSync()) {
      r = await Process.run(tar, [
        '--options',
        'hdrcharset=UTF-8',
        '-xf',
        archive.path,
        '-C',
        dest.path,
      ]);
    } else {
      r = await Process.run(
        'powershell',
        [
          '-NoProfile',
          '-Command',
          'Expand-Archive -LiteralPath \$env:RMK_SRC -DestinationPath \$env:RMK_DEST -Force',
        ],
        environment: {'RMK_SRC': archive.path, 'RMK_DEST': dest.path},
      );
    }
    if (r.exitCode != 0)
      throw ProcessException('tar', const [], '${r.stderr}'.trim(), r.exitCode);
  }
}
