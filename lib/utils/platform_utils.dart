import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// 平台相关的通用工具：数据目录、可执行文件查找、主目录等。
class PlatformUtils {
  PlatformUtils._();

  static Directory? _dataDir;

  /// 测试用：指定数据目录（不经过 path_provider）
  static void overrideDataDir(Directory dir) => _dataDir = dir;

  /// 应用数据目录（数据库、主密钥、传输目录都放在这里），首次调用时创建
  static Future<Directory> dataDir() async {
    if (_dataDir != null) return _dataDir!;
    final base = await getApplicationSupportDirectory();
    final dir = Directory(base.path);
    if (!dir.existsSync()) dir.createSync(recursive: true);
    _dataDir = dir;
    return dir;
  }

  /// 当前用户主目录
  static String homeDir() {
    return Platform.environment['HOME'] ?? Platform.environment['USERPROFILE'] ?? Directory.current.path;
  }

  /// 是否为类 Unix 桌面（macOS / Linux），部分功能（如系统免密登录）仅在这些平台提供
  static bool get isUnixDesktop => Platform.isMacOS || Platform.isLinux;

  /// 在 PATH 中查找可执行文件，找到返回绝对路径，否则返回 null
  static String? which(String name) {
    final pathEnv = Platform.environment['PATH'] ?? '';
    final sep = Platform.isWindows ? ';' : ':';
    final exts = Platform.isWindows ? ['.exe', '.bat', '.cmd', ''] : [''];
    // macOS 图形程序启动时 PATH 很短，补充常见目录（Homebrew 等）
    final extra = Platform.isMacOS ? ['/opt/homebrew/bin', '/usr/local/bin', '/opt/local/bin'] : <String>[];
    for (final dir in [...pathEnv.split(sep), ...extra]) {
      if (dir.isEmpty) continue;
      for (final ext in exts) {
        final f = File(p.join(dir, '$name$ext'));
        if (f.existsSync()) return f.path;
      }
    }
    return null;
  }

  /// 依次查找多个候选可执行文件，返回第一个存在的
  static String? whichAny(List<String> names) {
    for (final n in names) {
      final r = which(n);
      if (r != null) return r;
    }
    return null;
  }

  /// 在系统文件管理器中打开目录
  static Future<void> openInFileManager(String path) async {
    if (Platform.isMacOS) {
      await Process.run('open', [path]);
    } else if (Platform.isWindows) {
      await Process.run('explorer', [path]);
    } else {
      await Process.run('xdg-open', [path]);
    }
  }

  /// 将文件权限设置为仅当前用户可读写（非 Windows）
  static Future<void> restrictPermissions(String path) async {
    if (Platform.isWindows) return;
    try {
      await Process.run('chmod', ['600', path]);
    } catch (_) {
      // 设置权限失败不影响主流程
    }
  }
}
