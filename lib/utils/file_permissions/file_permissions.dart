import 'dart:io';

import 'file_permissions_posix.dart';
import 'file_permissions_windows.dart';

/// 把文件或目录的访问权限收紧为仅当前用户可访问（主密钥、Agent 登录凭据等敏感数据）。
/// 每个平台各自实现，修改时所有平台需要一起改（测试见 test/platform/platform_utils_test.dart）。
abstract class FilePermissions {
  /// 当前平台的实现
  factory FilePermissions.current() => Platform.isWindows ? WindowsFilePermissions() : PosixFilePermissions();

  /// 文件仅当前用户可读写，失败返回 false
  Future<bool> restrictFile(String path);

  /// 目录仅当前用户可访问（Windows 下目录中新建的文件也继承该权限），失败返回 false
  Future<bool> restrictDirectory(String path);
}
