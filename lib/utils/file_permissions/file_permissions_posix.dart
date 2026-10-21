import 'dart:io';

import 'file_permissions.dart';

/// macOS 与 Linux：chmod 600（文件）/ 700（目录）
class PosixFilePermissions implements FilePermissions {
  @override
  Future<bool> restrictFile(String path) => _chmod('600', path);

  @override
  Future<bool> restrictDirectory(String path) => _chmod('700', path);

  /// 调用系统 chmod
  Future<bool> _chmod(String mode, String path) async {
    try {
      final r = await Process.run('chmod', [mode, path]);
      return r.exitCode == 0;
    } catch (_) {
      return false;
    }
  }
}
