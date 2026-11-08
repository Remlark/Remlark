import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

import '../../utils/app_log.dart';
import '../../utils/id_utils.dart';
import '../../utils/shell_utils.dart';
import 'sftp_service.dart';

/// 传输方向
enum TransferDirection { upload, download }

/// 传输状态
enum TransferStatus { queued, running, done, failed, cancelled }

/// 一个传输任务（可能包含多个文件，例如上传整个目录）
class TransferTask extends ChangeNotifier {
  TransferTask({
    required this.direction,
    required this.name,
    required this.source,
    required this.target,
    this.remote,
    this.targetName,
  }) : id = IdUtils.newId();

  final String id;
  final TransferDirection direction;
  final String name;
  final String source;
  final String target;

  /// 下载任务的远程文件信息
  final FileEntry? remote;

  /// 在目标目录中使用的名称（上传重名时改名，如“文件 2.txt”；拖出下载时由系统给定）；为空保持原名
  final String? targetName;

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

  /// 是否失败（含取消），可重试
  bool get isFailed => status == TransferStatus.failed || status == TransferStatus.cancelled;

  /// 预计剩余时间（速度未知时为 null）
  Duration? get remaining {
    if (status != TransferStatus.running || speed <= 0 || total <= 0) return null;
    return Duration(seconds: ((total - transferred) / speed).ceil());
  }

  /// 进度通知间隔：分块很小（64KB）且速度可达 100MB/s 时，每块都通知会让界面每秒重建上千次
  static const _progressInterval = Duration(milliseconds: 100);
  DateTime _lastProgress = DateTime.fromMillisecondsSinceEpoch(0);

  /// 传输中的进度更新（限频）
  void _progress(int value) {
    transferred = value;
    final now = DateTime.now();
    if (now.difference(_lastProgress) < _progressInterval) return;
    _lastProgress = now;
    _update();
  }

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
  /// [autoRemoveDoneAfter] 非空时，成功完成的任务在该时长后自动从列表移除
  /// （用于远程桌面上的浮动传输框；SFTP 标签保留历史，不设置）
  TransferManager(this._sftp, {this.autoRemoveDoneAfter});

  final SftpService _sftp;
  final Duration? autoRemoveDoneAfter;
  final List<TransferTask> tasks = [];
  bool _running = false;
  bool _disposed = false;

  /// 传输完成回调（例如刷新 SFTP 目录）
  final List<void Function(TransferTask)> _onComplete = [];

  void addCompleteListener(void Function(TransferTask) l) => _onComplete.add(l);
  void removeCompleteListener(void Function(TransferTask) l) => _onComplete.remove(l);

  /// 活跃任务数量
  int get activeCount => tasks.where((t) => t.isActive).length;

  /// 上传本地文件或目录到远程目录；[asName] 指定远程名称（为空保持原名）
  TransferTask upload(String localPath, String remoteDir, {String? asName}) {
    final task = TransferTask(
      direction: TransferDirection.upload,
      name: asName ?? p.basename(localPath),
      source: localPath,
      target: remoteDir,
      targetName: asName,
    );
    _enqueue(task);
    return task;
  }

  /// 下载远程文件或目录到本地目录；[asName] 指定本地名称（为空保持原名，如拖到 Finder 时由系统给定名称）
  TransferTask download(FileEntry file, String localDir, {String? asName}) {
    final task = TransferTask(
      direction: TransferDirection.download,
      name: asName ?? file.name,
      source: file.path,
      target: localDir,
      remote: file,
      targetName: asName,
    );
    _enqueue(task);
    return task;
  }

  void _enqueue(TransferTask t) {
    AppLog.i('transfer', '排队 ${t.direction.name} ${t.source} → ${t.target}');
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

  /// 等待一组任务全部结束，返回是否全部成功
  static Future<bool> waitAll(List<TransferTask> tasks) async {
    while (tasks.any((t) => t.isActive)) {
      await Future.delayed(const Duration(milliseconds: 100));
    }
    return tasks.every((t) => t.status == TransferStatus.done);
  }

  /// 清除已完成的任务（保留失败任务以便重试）
  void clearFinished() {
    tasks.removeWhere((t) => t.status == TransferStatus.done);
    notifyListeners();
  }

  /// 移除一个已结束的任务（进行中的任务需先取消）
  void remove(TransferTask t) {
    if (t.isActive || !tasks.remove(t)) return;
    notifyListeners();
  }

  /// 成功的任务按 [autoRemoveDoneAfter] 延时移除；失败任务保留以便查看与重试
  void _scheduleAutoRemove(TransferTask t) {
    final delay = autoRemoveDoneAfter;
    if (delay == null || t.status != TransferStatus.done) return;
    Timer(delay, () {
      if (_disposed || !tasks.remove(t)) return;
      notifyListeners();
    });
  }

  /// 重试失败 / 已取消的任务：以相同参数重新排队
  TransferTask? retry(TransferTask t) {
    if (!t.isFailed) return null;
    tasks.remove(t);
    final remote = t.remote;
    if (t.direction == TransferDirection.download && remote != null) {
      return download(remote, t.target, asName: t.targetName);
    }
    return upload(t.source, t.target, asName: t.targetName);
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
        _scheduleAutoRemove(next);
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
      final ms = DateTime.now().difference(t._startedAt!).inMilliseconds;
      AppLog.i('transfer', '完成 ${t.name}：${t.fileCount} 个文件 ${t.total} 字节，耗时 ${ms}ms');
    } on TransferCancelled {
      t.status = TransferStatus.cancelled;
      AppLog.i('transfer', '已取消 ${t.name}');
    } catch (e, st) {
      t.status = t.cancelToken.isCancelled ? TransferStatus.cancelled : TransferStatus.failed;
      t.error = '$e';
      AppLog.e('transfer', '失败 ${t.name}（${t.source} → ${t.target}）', e, st);
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
      var relPath = rel.replaceAll('\\', '/');
      // 指定了目标名称时替换最外层名称（文件名或目录名）
      final rename = t.targetName;
      if (rename != null) {
        final slash = relPath.indexOf('/');
        relPath = slash < 0 ? rename : '$rename${relPath.substring(slash)}';
      }
      final remotePath = ShellUtils.joinRemote(t.target, relPath);
      await _sftp.ensureRemoteDir(ShellUtils.parentRemote(remotePath));
      final start = base;
      await _sftp.uploadFile(local, remotePath, cancel: t.cancelToken, onProgress: (n) => t._progress(start + n));
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
    // 先建好顶层目录：空目录也要在本地出现（拖到 Finder 时系统等待该目录）
    if (remote.isDir) Directory(p.join(t.target, t.targetName ?? remote.name)).createSync(recursive: true);
    var base = 0;
    for (final (remotePath, rel, size) in files) {
      if (t.cancelToken.isCancelled) throw TransferCancelled();
      final parts = rel.split('/');
      // 指定了目标名称时替换最外层名称（文件名或目录名）
      if (t.targetName != null) parts[0] = t.targetName!;
      final localPath = p.joinAll([t.target, ...parts]);
      Directory(p.dirname(localPath)).createSync(recursive: true);
      final start = base;
      await _sftp.downloadFile(remotePath, localPath, cancel: t.cancelToken, onProgress: (n) => t._progress(start + n));
      base += size;
      t.transferred = base;
      t.filesDone++;
      t._update();
    }
  }

  @override
  void dispose() {
    _disposed = true;
    for (final t in tasks) {
      t.cancelToken.cancel();
    }
    super.dispose();
  }
}
