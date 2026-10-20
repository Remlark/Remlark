import 'dart:io';

import 'package:path/path.dart' as p;

import '../../utils/platform_utils.dart';
import '../../utils/shell_utils.dart';
import 'sftp_service.dart';

/// 文件来源接口：SFTP 双栏浏览器的本地栏与远程栏共用同一套界面，通过该接口访问各自的文件系统
abstract class FileSource {
  /// 是否为远程文件系统
  bool get isRemote;

  /// 起始目录（用户主目录）
  Future<String> home();

  /// 列出目录（目录在前，按名称排序）
  Future<List<FileEntry>> list(String path);

  /// 新建目录
  Future<void> mkdir(String path);

  /// 重命名
  Future<void> rename(String from, String to);

  /// 删除文件或目录（目录递归删除）
  Future<void> delete(FileEntry f);

  /// 拼接路径
  String join(String dir, String name);

  /// 上级目录
  String parent(String path);
}

/// 远程文件来源：基于 SFTP
class RemoteFileSource implements FileSource {
  RemoteFileSource(this.sftp);

  final SftpService sftp;

  @override
  bool get isRemote => true;

  @override
  Future<String> home() => sftp.home();

  @override
  Future<List<FileEntry>> list(String path) => sftp.list(path);

  @override
  Future<void> mkdir(String path) => sftp.mkdir(path);

  @override
  Future<void> rename(String from, String to) => sftp.rename(from, to);

  @override
  Future<void> delete(FileEntry f) => sftp.delete(f.path, isDir: f.isDir && !f.isLink);

  @override
  String join(String dir, String name) => ShellUtils.joinRemote(dir, name);

  @override
  String parent(String path) => ShellUtils.parentRemote(path);
}

/// 本地文件来源：基于 dart:io，三个平台通用
class LocalFileSource implements FileSource {
  @override
  bool get isRemote => false;

  @override
  Future<String> home() async => PlatformUtils.homeDir();

  @override
  Future<List<FileEntry>> list(String path) async {
    final files = <FileEntry>[];
    await for (final e in Directory(path).list(followLinks: false)) {
      final name = p.basename(e.path);
      final isLink = e is Link;
      FileStat stat;
      try {
        stat = isLink ? await FileStat.stat(e.path) : await e.stat();
      } catch (_) {
        continue;
      }
      final isDir = stat.type == FileSystemEntityType.directory;
      files.add(
        FileEntry(
          name: name,
          path: e.path,
          isDir: isDir,
          isLink: isLink,
          size: isDir ? 0 : stat.size,
          modified: stat.modified.millisecondsSinceEpoch ~/ 1000,
        ),
      );
    }
    files.sort((a, b) {
      if (a.isDir != b.isDir) return a.isDir ? -1 : 1;
      return a.name.toLowerCase().compareTo(b.name.toLowerCase());
    });
    return files;
  }

  @override
  Future<void> mkdir(String path) => Directory(path).create();

  @override
  Future<void> rename(String from, String to) async {
    if (await FileSystemEntity.isDirectory(from)) {
      await Directory(from).rename(to);
    } else {
      await File(from).rename(to);
    }
  }

  @override
  Future<void> delete(FileEntry f) async {
    if (f.isLink) {
      await Link(f.path).delete();
    } else if (f.isDir) {
      await Directory(f.path).delete(recursive: true);
    } else {
      await File(f.path).delete();
    }
  }

  @override
  String join(String dir, String name) => p.join(dir, name);

  @override
  String parent(String path) => p.dirname(path);
}
