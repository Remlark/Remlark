import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:dartssh2/dartssh2.dart';
import 'package:path/path.dart' as p;

import '../../utils/shell_utils.dart';

/// 文件条目（远程 SFTP 与本地文件系统共用）
class FileEntry {
  const FileEntry({
    required this.name,
    required this.path,
    required this.isDir,
    required this.isLink,
    required this.size,
    this.modified,
    this.permissions = '',
  });

  final String name;
  final String path;
  final bool isDir;
  final bool isLink;
  final int size;
  final int? modified;
  final String permissions;
}

/// 传输取消标志
class CancelToken {
  bool _cancelled = false;
  final List<void Function()> _listeners = [];

  bool get isCancelled => _cancelled;

  /// 取消并通知监听者
  void cancel() {
    if (_cancelled) return;
    _cancelled = true;
    for (final l in _listeners) {
      l();
    }
  }

  void onCancel(void Function() l) => _listeners.add(l);
}

/// 传输被取消
class TransferCancelled implements Exception {}

/// SFTP 服务：在一个 SSH 连接上懒加载 SFTP 子系统，提供目录与文件操作
class SftpService {
  SftpService(this._client);

  final SSHClient _client;
  SftpClient? _sftp;
  Future<SftpClient>? _opening;

  /// 获取（必要时打开）SFTP 客户端
  Future<SftpClient> get sftp async {
    if (_sftp != null) return _sftp!;
    _opening ??= _client.sftp().then((s) => _sftp = s);
    return _opening!;
  }

  /// 远程用户主目录
  Future<String> home() async => (await sftp).absolute('.');

  /// 列出目录（目录在前，按名称排序）
  Future<List<FileEntry>> list(String path) async {
    final names = await (await sftp).listdir(path);
    final files = <FileEntry>[];
    for (final n in names) {
      if (n.filename == '.' || n.filename == '..') continue;
      final full = ShellUtils.joinRemote(path, n.filename);
      var isDir = n.attr.isDirectory;
      final isLink = n.attr.isSymbolicLink;
      if (isLink) {
        // 符号链接：判断指向的是否为目录
        try {
          isDir = (await (await sftp).stat(full)).isDirectory;
        } catch (_) {}
      }
      files.add(
        FileEntry(
          name: n.filename,
          path: full,
          isDir: isDir,
          isLink: isLink,
          size: n.attr.size ?? 0,
          modified: n.attr.modifyTime,
          permissions: n.longname.split(' ').first,
        ),
      );
    }
    files.sort((a, b) {
      if (a.isDir != b.isDir) return a.isDir ? -1 : 1;
      return a.name.toLowerCase().compareTo(b.name.toLowerCase());
    });
    return files;
  }

  /// 新建目录
  Future<void> mkdir(String path) async => (await sftp).mkdir(path);

  /// 重命名 / 移动
  Future<void> rename(String from, String to) async => (await sftp).rename(from, to);

  /// 删除文件或目录（目录递归删除）
  Future<void> delete(String path, {required bool isDir}) async {
    final s = await sftp;
    if (!isDir) {
      await s.remove(path);
      return;
    }
    for (final f in await list(path)) {
      await delete(f.path, isDir: f.isDir && !f.isLink);
    }
    await s.rmdir(path);
  }

  /// 是否存在
  /// 获取单个路径的信息（用于构造下载任务）
  Future<FileEntry> statEntry(String path) async {
    final a = await (await sftp).stat(path);
    return FileEntry(
      name: ShellUtils.basenameRemote(path),
      path: path,
      isDir: a.isDirectory,
      isLink: false,
      size: a.size ?? 0,
      modified: a.modifyTime,
    );
  }

  Future<bool> exists(String path) async {
    try {
      await (await sftp).stat(path);
      return true;
    } catch (_) {
      return false;
    }
  }

  /// 上传本地文件到 [remotePath]，[onProgress] 回调已传输字节数
  Future<void> uploadFile(
    String localPath,
    String remotePath, {
    void Function(int sent)? onProgress,
    CancelToken? cancel,
  }) async {
    final s = await sftp;
    final file = await s.open(
      remotePath,
      mode: SftpFileOpenMode.create | SftpFileOpenMode.truncate | SftpFileOpenMode.write,
    );
    try {
      final writer = file.write(File(localPath).openRead().map(Uint8List.fromList), onProgress: onProgress);
      cancel?.onCancel(() => writer.abort());
      await writer.done;
      if (cancel?.isCancelled == true) throw TransferCancelled();
    } finally {
      await file.close();
    }
  }

  /// 下载远程文件到本地 [localPath]
  Future<void> downloadFile(
    String remotePath,
    String localPath, {
    void Function(int received)? onProgress,
    CancelToken? cancel,
  }) async {
    final s = await sftp;
    final file = await s.open(remotePath, mode: SftpFileOpenMode.read);
    final sink = File(localPath).openWrite();
    var received = 0;
    try {
      await for (final chunk in file.read()) {
        if (cancel?.isCancelled == true) throw TransferCancelled();
        sink.add(chunk);
        received += chunk.length;
        onProgress?.call(received);
      }
    } finally {
      await sink.close();
      await file.close();
    }
  }

  /// 统计本地路径（文件或目录）的总大小与文件列表（相对路径）
  static Future<List<(String local, String rel, int size)>> walkLocal(String localPath) async {
    final type = FileSystemEntity.typeSync(localPath);
    final base = p.basename(localPath);
    if (type == FileSystemEntityType.file) {
      return [(localPath, base, File(localPath).lengthSync())];
    }
    final result = <(String, String, int)>[];
    await for (final e in Directory(localPath).list(recursive: true, followLinks: false)) {
      if (e is File) {
        final rel = p.join(base, p.relative(e.path, from: localPath));
        result.add((e.path, rel, e.lengthSync()));
      }
    }
    return result;
  }

  /// 统计远程目录下的所有文件（相对路径）
  Future<List<(String remote, String rel, int size)>> walkRemote(FileEntry root) async {
    if (!root.isDir) return [(root.path, root.name, root.size)];
    final result = <(String, String, int)>[];
    Future<void> walk(String dir, String rel) async {
      for (final f in await list(dir)) {
        final r = '$rel/${f.name}';
        if (f.isDir && !f.isLink) {
          await walk(f.path, r);
        } else {
          result.add((f.path, r, f.size));
        }
      }
    }

    await walk(root.path, root.name);
    return result;
  }

  /// 确保远程目录存在（逐级创建）
  Future<void> ensureRemoteDir(String dir) async {
    if (dir.isEmpty || dir == '/') return;
    if (await exists(dir)) return;
    await ensureRemoteDir(ShellUtils.parentRemote(dir));
    try {
      await mkdir(dir);
    } catch (_) {
      // 并发创建时可能已存在
    }
  }

  /// 关闭 SFTP 子系统
  void close() {
    _sftp?.close();
    _sftp = null;
    _opening = null;
  }
}
