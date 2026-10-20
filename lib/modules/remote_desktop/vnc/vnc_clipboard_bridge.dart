import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart' show AppLifecycleListener;
import 'package:pasteboard/pasteboard.dart';
import 'package:path/path.dart' as p;

import '../../../utils/app_log.dart';
import '../../../utils/platform_utils.dart';
import '../../../utils/shell_utils.dart';
import '../../sftp/sftp_service.dart';
import '../../sftp/transfer_manager.dart';
import '../../ssh/ssh_connector.dart';
import '../../ssh/ssh_exec.dart';
import 'finder_locator.dart';
import 'lazy_file_clipboard.dart';
import 'ssh_clipboard.dart';

/// 剪贴板提示（多语言 key + 参数），由界面显示
typedef ClipboardNotice = void Function(String key, Map<String, Object> args, {bool error});

/// VNC 剪贴板桥：本地与远程 macOS 之间双向同步文本与文件。
///
/// - 本地 → 远程文本：复制后自动推送（RFB 消息 + SSH pbcopy）
/// - 本地 → 远程文件：在 VNC 中按 ⌘V 时拦截；远程最前面是 Finder 时直接上传到 Finder 的插入位置
///   （顶层窗口所在文件夹，无窗口为桌面），同名按 Finder 规则改名；其他应用则上传到远程缓存目录、
///   写入远程剪贴板后再补发 ⌘V，由该应用处理粘贴
/// - 远程 → 本地：在 VNC 中按 ⌘C / ⌘X 后、或离开本应用时读取远程剪贴板；文件只在本地剪贴板放入占位项，
///   在本地粘贴时才下载（macOS，见 LazyFileClipboard），由 Finder 放到其顶层窗口或桌面；文本直接写入本地剪贴板
///
/// 文件经关联 SSH 主机传输；剪贴板不受隐私权限限制，SSH 会话可直接读写。
class VncClipboardBridge {
  VncClipboardBridge({
    required this.hasSsh,
    required this.connectSsh,
    required this.transfers,
    required this.sendRfbText,
    required this.sendKey,
    required this.isKeyDown,
  });

  /// 是否配置了关联 SSH 主机
  final bool Function() hasSsh;

  /// 建立（或复用）关联 SSH 主机连接
  final Future<SshConnection> Function() connectSsh;

  /// 传输队列（连接后可用）
  final TransferManager? Function() transfers;

  /// 发送 RFB 剪贴板消息
  final void Function(String text) sendRfbText;

  /// 发送按键（X11 keysym）
  final void Function(int keysym, bool down) sendKey;

  /// 某个 keysym 当前是否按下（远程视角）
  final bool Function(int keysym) isKeyDown;

  /// 界面提示
  ClipboardNotice? onNotice;

  /// 是否开启剪贴板同步
  bool enabled = true;

  static const _keyV = 0x76;
  static const _superL = 0xffeb;
  static const _superR = 0xffec;

  /// 远程 / 本地缓存目录保留的批次数
  static const _keepBatches = 5;

  String? _lastText;
  List<String> _localFiles = const [];
  int? _lastRemoteChange;
  bool _pushBusy = false;
  bool _pullBusy = false;
  bool _pasting = false;
  bool _swallowVUp = false;
  String? _sshUnavailable;
  AppLifecycleListener? _lifecycle;

  /// 新连接建立时调用：重置状态、记录远程剪贴板基线、监听应用切换
  void start() {
    _lastText = null;
    _localFiles = const [];
    _lastRemoteChange = null;
    _sshUnavailable = null;
    _lifecycle?.dispose();
    // 离开本应用（去本地粘贴）时拉取远程剪贴板；回到本应用时推送本地剪贴板
    _lifecycle = AppLifecycleListener(
      onInactive: () => unawaited(pullRemote()),
      onResume: () => unawaited(pushLocal()),
    );
    unawaited(_baseline());
  }

  /// 断开时调用
  void stop() {
    _lifecycle?.dispose();
    _lifecycle = null;
  }

  /// 记录远程剪贴板当前的变化计数，之后只同步新的复制
  Future<void> _baseline() async {
    final conn = await _ssh();
    if (conn == null) return;
    final pb = await SshClipboard.read(conn.client);
    _lastRemoteChange ??= pb?.changeCount;
  }

  /// 获取 SSH 连接；不可用时返回 null（本次连接期间不再尝试）
  Future<SshConnection?> _ssh() async {
    if (_sshUnavailable != null) return null;
    if (!hasSsh()) {
      _sshUnavailable = 'no ssh';
      AppLog.i('clipboard', '未配置关联 SSH 主机：仅 RFB 文本剪贴板，文件复制粘贴不可用');
      return null;
    }
    try {
      return await connectSsh();
    } catch (e) {
      _sshUnavailable = '$e';
      AppLog.w('clipboard', '连接关联 SSH 主机失败，本次连接不再经 SSH 同步剪贴板', e);
      return null;
    }
  }

  // ---------- 本地 → 远程 ----------

  /// 检查本地剪贴板：文件则记录（等待 ⌘V），文本则推送到远程
  Future<void> pushLocal() async {
    if (!enabled || _pushBusy) return;
    _pushBusy = true;
    try {
      // 剪贴板是本程序放入的远程文件占位项：不能读取（读取文件会触发下载），也无需推送
      if (await LazyFileClipboard.instance.ownsClipboard()) return;
      List<String> files = const [];
      try {
        files = await Pasteboard.files();
      } catch (_) {}
      if (files.isNotEmpty) {
        // 复制文件时剪贴板同时含文件名文本，不能当作文本推送，否则会覆盖远程的文件剪贴板
        if (!_sameList(files, _localFiles)) _localFiles = files;
        return;
      }
      _localFiles = const [];
      final String? text;
      try {
        text = (await Clipboard.getData(Clipboard.kTextPlain))?.text;
      } catch (e) {
        AppLog.w('clipboard', '读取本地剪贴板失败', e);
        return;
      }
      // 空文本不推送（否则会把远程剪贴板清空）
      if (text == null || text.isEmpty || text == _lastText) return;
      _lastText = text;
      sendRfbText(text);
      final conn = await _ssh();
      if (conn != null) await SshClipboard.write(conn.client, text);
    } finally {
      _pushBusy = false;
    }
  }

  /// 处理按键：⌘V 且本地剪贴板为文件时拦截并粘贴文件；⌘C / ⌘X 后拉取远程剪贴板。
  /// 返回 true 表示已处理，调用方不应再转发给远程
  bool handleKey(KeyEvent e) {
    if (!enabled) return false;
    final isV = e.logicalKey == LogicalKeyboardKey.keyV;
    if (isV && e is KeyUpEvent && _swallowVUp) {
      _swallowVUp = false;
      return true;
    }
    if (isV && e is KeyRepeatEvent && _pasting) return true;
    final k = HardwareKeyboard.instance;
    final cmd = k.isMetaPressed || k.isControlPressed;
    if (!cmd || e is! KeyDownEvent) return false;
    if (isV && _localFiles.isNotEmpty && !_pasting) {
      _swallowVUp = true;
      unawaited(_pasteFiles(List.of(_localFiles)));
      return true;
    }
    if (e.logicalKey == LogicalKeyboardKey.keyC || e.logicalKey == LogicalKeyboardKey.keyX) {
      // 等远程应用完成复制后再读取
      Timer(const Duration(milliseconds: 600), () => unawaited(pullRemote()));
    }
    return false;
  }

  /// 粘贴本地文件到远程
  Future<void> _pasteFiles(List<String> files) async {
    _pasting = true;
    try {
      final conn = await _ssh();
      final tm = transfers();
      if (conn == null || tm == null) {
        onNotice?.call('clip.no_ssh', const {}, error: true);
        return;
      }
      final front = await SshClipboard.frontApp(conn.client);
      if (front == null || front == 'com.apple.finder') {
        await _pasteToFinder(conn, tm, files);
      } else {
        await _pasteToApp(conn, tm, files, front);
      }
    } catch (e, st) {
      AppLog.e('clipboard', '粘贴文件失败', e, st);
      onNotice?.call('clip.failed', {'detail': '$e'}, error: true);
    } finally {
      _pasting = false;
    }
  }

  /// 远程最前面是 Finder：直接上传到 Finder 插入位置（顶层窗口文件夹或桌面）
  Future<void> _pasteToFinder(SshConnection conn, TransferManager tm, List<String> files) async {
    final r = await FinderLocator.query(conn.client);
    final layout = r.layout;
    if (layout == null) {
      AppLog.w('clipboard', '无法获取 Finder 插入位置：${r.error} ${r.detail ?? ''}');
      onNotice?.call(r.error!, {'detail': r.detail ?? ''}, error: true);
      return;
    }
    final dir = layout.insertion ?? layout.folderAt(null, 0);
    final sftp = SftpService(conn.client);
    final existing = {for (final f in await sftp.list(dir)) f.name};
    final tasks = <TransferTask>[];
    for (final f in files) {
      final isDir = FileSystemEntity.isDirectorySync(f);
      final name = ShellUtils.uniqueName(p.basename(f), existing, isDir: isDir);
      existing.add(name);
      tasks.add(tm.upload(f, dir, asName: name == p.basename(f) ? null : name));
    }
    onNotice?.call('clip.pasting', {'count': files.length, 'dir': dir});
    await TransferManager.waitAll(tasks);
  }

  /// 远程最前面是其他应用：上传到远程缓存目录、写入远程剪贴板，再补发 ⌘V 交给该应用
  Future<void> _pasteToApp(SshConnection conn, TransferManager tm, List<String> files, String app) async {
    final sftp = SftpService(conn.client);
    final root = ShellUtils.joinRemote(await sftp.home(), 'Library/Caches/Remlark/clipboard');
    final dir = ShellUtils.joinRemote(root, '${DateTime.now().millisecondsSinceEpoch}');
    await sftp.ensureRemoteDir(dir);
    onNotice?.call('clip.pasting', {'count': files.length, 'dir': app});
    final tasks = [for (final f in files) tm.upload(f, dir)];
    if (!await TransferManager.waitAll(tasks)) {
      onNotice?.call('clip.failed', {'detail': 'upload failed'}, error: true);
      return;
    }
    final remotePaths = [for (final f in files) ShellUtils.joinRemote(dir, p.basename(f))];
    final cc = await SshClipboard.writeFiles(conn.client, remotePaths);
    if (cc == null) {
      onNotice?.call('clip.failed', {'detail': 'pasteboard'}, error: true);
      return;
    }
    // 这次变化是自己写入的，拉取时忽略
    _lastRemoteChange = cc;
    _sendPasteKeys();
    unawaited(_cleanupRemote(conn, root));
  }

  /// 补发 ⌘V：用户已松开 ⌘ 时临时按下
  void _sendPasteKeys() {
    final held = isKeyDown(_superL) || isKeyDown(_superR);
    if (!held) sendKey(_superL, true);
    sendKey(_keyV, true);
    sendKey(_keyV, false);
    if (!held) sendKey(_superL, false);
  }

  /// 远程缓存只保留最近几批
  Future<void> _cleanupRemote(SshConnection conn, String root) async {
    try {
      await SshExec.run(
        conn.client,
        'cd ${ShellUtils.quote(root)} && ls -1t | tail -n +${_keepBatches + 1} | while read d; do rm -rf "\$d"; done',
      );
    } catch (e) {
      AppLog.w('clipboard', '清理远程剪贴板缓存失败', e);
    }
  }

  // ---------- 远程 → 本地 ----------

  /// 读取远程剪贴板，有新内容时写入本地：文件下载到本地缓存后写入文件剪贴板，文本直接写入
  Future<void> pullRemote() async {
    if (!enabled || _pullBusy) return;
    _pullBusy = true;
    try {
      final conn = await _ssh();
      if (conn == null) return;
      final pb = await SshClipboard.read(conn.client);
      if (pb == null) return;
      if (pb.changeCount == _lastRemoteChange) return;
      _lastRemoteChange = pb.changeCount;
      if (pb.files.isNotEmpty) {
        await _pullFiles(conn, pb.files);
      } else if (pb.text != null && pb.text != _lastText) {
        _lastText = pb.text;
        await Clipboard.setData(ClipboardData(text: pb.text!));
      }
    } catch (e, st) {
      AppLog.e('clipboard', '拉取远程剪贴板失败', e, st);
    } finally {
      _pullBusy = false;
    }
  }

  /// 远程复制了文件：支持延迟提供的平台（macOS）只放入占位项，本地粘贴时才下载；
  /// 其他平台立即下载到本地缓存并写入文件剪贴板
  Future<void> _pullFiles(SshConnection conn, List<String> remote) async {
    final lazy = LazyFileClipboard.instance;
    if (lazy.supported) {
      final batch = await _newLocalBatch();
      // 每次远程复制使用独立的本地目录，粘贴时按需下载到这里
      lazy.onProvide = (id) => _provideFile(id, batch);
      final ok = await lazy.offer(remote);
      _localFiles = const [];
      onNotice?.call(ok ? 'clip.copied' : 'clip.failed', {'count': remote.length, 'detail': 'pasteboard'}, error: !ok);
      return;
    }
    final tm = transfers();
    if (tm == null) return;
    final dir = await _newLocalBatch();
    onNotice?.call('clip.pulling', {'count': remote.length});
    final sftp = SftpService(conn.client);
    final tasks = <TransferTask>[];
    for (final f in remote) {
      tasks.add(tm.download(await sftp.statEntry(f), dir.path));
    }
    if (!await TransferManager.waitAll(tasks)) {
      onNotice?.call('clip.failed', {'detail': 'download failed'}, error: true);
      return;
    }
    final local = [for (final f in remote) p.join(dir.path, ShellUtils.basenameRemote(f))];
    final ok = await Pasteboard.writeFiles(local);
    // 本地剪贴板现在是这些文件，记录下来，避免被当作新的本地复制
    _localFiles = local;
    onNotice?.call(ok ? 'clip.pulled' : 'clip.failed', {'count': local.length, 'detail': 'pasteboard'}, error: !ok);
  }

  /// 本地粘贴请求某个远程文件时下载（传输进度此时才显示），返回本地路径
  Future<String?> _provideFile(String remotePath, Directory batch) async {
    final local = p.join(batch.path, ShellUtils.basenameRemote(remotePath));
    // 同一次复制可能被多次粘贴：已下载则直接复用
    if (FileSystemEntity.typeSync(local) != FileSystemEntityType.notFound) return local;
    final conn = await _ssh();
    final tm = transfers();
    if (conn == null || tm == null) {
      AppLog.w('clipboard', '粘贴时无法连接传输主机，无法提供 $remotePath');
      onNotice?.call('clip.failed', {'detail': 'ssh'}, error: true);
      return null;
    }
    try {
      onNotice?.call('clip.pulling', {'count': 1});
      final task = tm.download(await SftpService(conn.client).statEntry(remotePath), batch.path);
      final ok = await TransferManager.waitAll([task]);
      if (!ok) {
        onNotice?.call('clip.failed', {'detail': task.error ?? 'download failed'}, error: true);
        return null;
      }
      return local;
    } catch (e, st) {
      AppLog.e('clipboard', '粘贴下载失败 $remotePath', e, st);
      onNotice?.call('clip.failed', {'detail': '$e'}, error: true);
      return null;
    }
  }

  /// 新建一个本地缓存批次目录（并清理旧批次）
  Future<Directory> _newLocalBatch() async {
    final root = Directory(p.join((await PlatformUtils.dataDir()).path, 'clipboard'));
    final dir = Directory(p.join(root.path, '${DateTime.now().millisecondsSinceEpoch}'))..createSync(recursive: true);
    _cleanupLocal(root);
    return dir;
  }

  /// 本地缓存只保留最近几批
  void _cleanupLocal(Directory root) {
    try {
      final dirs = root.listSync().whereType<Directory>().toList()
        ..sort((a, b) => b.statSync().modified.compareTo(a.statSync().modified));
      for (final d in dirs.skip(_keepBatches)) {
        d.deleteSync(recursive: true);
      }
    } catch (e) {
      AppLog.w('clipboard', '清理本地剪贴板缓存失败', e);
    }
  }

  /// 远程收到的 RFB 剪贴板文本（非 macOS 服务端）
  void onRemoteText(String text) {
    if (!enabled) return;
    _lastText = text;
    Clipboard.setData(ClipboardData(text: text));
  }

  static bool _sameList(List<String> a, List<String> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}
