import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

import '../../utils/id_utils.dart';
import '../../utils/shell_utils.dart';
import 'sftp_service.dart';

/// 传输方向
enum TransferDirection { upload, download }

/// 传输状态
enum TransferStatus { queued, running, done, failed, cancelled }

/// 一个传输任务（可能包含多个文件，例如上传整个目录）
class TransferTask extends ChangeNotifier {
  TransferTask({required this.direction, required this.name, required this.source, required this.target, this.remote})
    : id = IdUtils.newId();

  final String id;
  final TransferDirection direction;
  final String name;
  final String source;
  final String target;

  /// 下载任务的远程文件信息
  final RemoteFile? remote;

  TransferStatus status = TransferStatus.queued;
  int total = 0;
  int transferred = 0;
  int fileCount = 0;
  int filesDone = 0;
  String? error;
  double speed = 0;
  final CancelToken cancelToken = CancelToken();

  DateTime? _startedAt;

  /// 进度 0~1
  double get progress => total <= 0 ? 0 : (transferred / total).clamp(0, 1);

  bool get isActive => status == TransferStatus.queued || status == TransferStatus.running;

  void _update() {
    final started = _startedAt;
    if (started != null) {
      final ms = DateTime.now().difference(started).inMilliseconds;
      if (ms > 0) speed = transferred * 1000 / ms;
    }
    notifyListeners();
  }
}

/// 传输管理器：串行执行队列中的任务，提供进度反馈
class TransferManager extends ChangeNotifier {
  TransferManager(this._sftp);

  final SftpService _sftp;
  final List<TransferTask> tasks = [];
  bool _running = false;

  /// 传输完成回调（例如刷新 SFTP 目录）
  final List<void Function(TransferTask)> _onComplete = [];

  void addCompleteListener(void Function(TransferTask) l) => _onComplete.add(l);
  void removeCompleteListener(void Function(TransferTask) l) => _onComplete.remove(l);

  /// 活跃任务数量
  int get activeCount => tasks.where((t) => t.isActive).length;

  /// 上传本地文件或目录到远程目录
  TransferTask upload(String localPath, String remoteDir) {
    final task = TransferTask(
      direction: TransferDirection.upload,
      name: p.basename(localPath),
      source: localPath,
      target: remoteDir,
    );
    _enqueue(task);
    return task;
  }

  /// 下载远程文件或目录到本地目录
  TransferTask download(RemoteFile file, String localDir) {
    final task = TransferTask(
      direction: TransferDirection.download,
      name: file.name,
      source: file.path,
      target: localDir,
      remote: file,
    );
    _enqueue(task);
    return task;
  }

  void _enqueue(TransferTask t) {
    tasks.insert(0, t);
    notifyListeners();
    _pump();
  }

  /// 取消任务
  void cancel(TransferTask t) {
    t.cancelToken.cancel();
    if (t.status == TransferStatus.queued) {
      t.status = TransferStatus.cancelled;
      t._update();
      notifyListeners();
    }
  }

  /// 清除已结束的任务
  void clearFinished() {
    tasks.removeWhere((t) => !t.isActive);
    notifyListeners();
  }

  /// 依次执行队列
  Future<void> _pump() async {
    if (_running) return;
    _running = true;
    try {
      while (true) {
        final next = tasks.reversed.where((t) => t.status == TransferStatus.queued).firstOrNull;
        if (next == null) break;
        await _run(next);
        for (final l in List.of(_onComplete)) {
          l(next);
        }
        notifyListeners();
      }
    } finally {
      _running = false;
    }
  }

  Future<void> _run(TransferTask t) async {
    t.status = TransferStatus.running;
    t._startedAt = DateTime.now();
    t._update();
    notifyListeners();
    try {
      if (t.direction == TransferDirection.upload) {
        await _runUpload(t);
      } else {
        await _runDownload(t);
      }
      t.status = TransferStatus.done;
    } on TransferCancelled {
      t.status = TransferStatus.cancelled;
    } catch (e) {
      t.status = t.cancelToken.isCancelled ? TransferStatus.cancelled : TransferStatus.failed;
      t.error = '$e';
    }
    t._update();
  }

  Future<void> _runUpload(TransferTask t) async {
    final files = await SftpService.walkLocal(t.source);
    t.fileCount = files.length;
    t.total = files.fold(0, (s, f) => s + f.$3);
    t._update();
    var base = 0;
    for (final (local, rel, size) in files) {
      if (t.cancelToken.isCancelled) throw TransferCancelled();
      final remotePath = ShellUtils.joinRemote(t.target, rel.replaceAll('\\', '/'));
      await _sftp.ensureRemoteDir(ShellUtils.parentRemote(remotePath));
      final start = base;
      await _sftp.uploadFile(
        local,
        remotePath,
        cancel: t.cancelToken,
        onProgress: (n) {
          t.transferred = start + n;
          t._update();
        },
      );
      base += size;
      t.transferred = base;
      t.filesDone++;
      t._update();
    }
  }

  Future<void> _runDownload(TransferTask t) async {
    final remote = t.remote!;
    final files = await _sftp.walkRemote(remote);
    t.fileCount = files.length;
    t.total = files.fold(0, (s, f) => s + f.$3);
    t._update();
    var base = 0;
    for (final (remotePath, rel, size) in files) {
      if (t.cancelToken.isCancelled) throw TransferCancelled();
      final localPath = p.joinAll([t.target, ...rel.split('/')]);
      Directory(p.dirname(localPath)).createSync(recursive: true);
      final start = base;
      await _sftp.downloadFile(
        remotePath,
        localPath,
        cancel: t.cancelToken,
        onProgress: (n) {
          t.transferred = start + n;
          t._update();
        },
      );
      base += size;
      t.transferred = base;
      t.filesDone++;
      t._update();
    }
  }

  @override
  void dispose() {
    for (final t in tasks) {
      t.cancelToken.cancel();
    }
    super.dispose();
  }
}
