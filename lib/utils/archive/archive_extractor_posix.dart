import 'dart:io';

import 'archive_extractor.dart';

/// macOS 与 Linux：系统 tar（.tar.gz）或 unzip（.zip）
class PosixArchiveExtractor implements ArchiveExtractor {
  @override
  Future<void> extract(File archive, Directory dest) async {
    final zip = archive.path.toLowerCase().endsWith('.zip');
    final r = zip
        ? await Process.run('unzip', ['-q', '-o', archive.path, '-d', dest.path])
        : await Process.run('tar', ['-xzf', archive.path, '-C', dest.path]);
    if (r.exitCode != 0) throw ProcessException(zip ? 'unzip' : 'tar', const [], '${r.stderr}'.trim(), r.exitCode);
  }
}
