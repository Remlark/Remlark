import 'dart:io';

import 'file_permissions.dart';

/// Windows：用系统 icacls 去掉继承的权限，只给当前用户完全控制
class WindowsFilePermissions implements FilePermissions {
  WindowsFilePermissions({String? user}) : _user = user ?? currentUser();

  /// 授权的账户（`域\用户名`），取不到时不修改权限
  final String? _user;

  /// 当前登录账户：优先 `USERDOMAIN\USERNAME`，没有域时只用用户名
  static String? currentUser() {
    final env = Platform.environment;
    final name = env['USERNAME'];
    if (name == null || name.isEmpty) return null;
    final domain = env['USERDOMAIN'];
    return domain == null || domain.isEmpty ? name : '$domain\\$name';
  }

  /// icacls 参数：`/inheritance:r` 删除继承的权限，`/grant:r` 替换为只有 [user] 完全控制；
  /// 目录加 (OI)(CI)，让其中的文件和子目录继承同样的权限
  static List<String> icaclsArgs(String path, String user, {required bool directory}) => [
    path,
    '/inheritance:r',
    '/grant:r',
    directory ? '$user:(OI)(CI)F' : '$user:F',
  ];

  @override
  Future<bool> restrictFile(String path) => _icacls(path, directory: false);

  @override
  Future<bool> restrictDirectory(String path) => _icacls(path, directory: true);

  /// 调用系统 icacls（System32 下的完整路径，避免 PATH 中的同名程序）
  Future<bool> _icacls(String path, {required bool directory}) async {
    final user = _user;
    if (user == null) return false;
    final systemRoot = Platform.environment['SystemRoot'] ?? r'C:\Windows';
    try {
      final r = await Process.run('$systemRoot\\System32\\icacls.exe', icaclsArgs(path, user, directory: directory));
      return r.exitCode == 0;
    } catch (_) {
      return false;
    }
  }
}
