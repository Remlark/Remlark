import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart' show KeyEventResult;

import '../../../utils/app_log.dart';
import '../../sftp/sftp_service.dart';
import '../../sftp/transfer_manager.dart';
import '../../ssh/ssh_connector.dart';
import '../../ssh/ssh_interaction.dart';
import '../../hosts/host_model.dart';
import '../../hosts/host_repository.dart';
import '../../hosts/vnc_ssh_config.dart';
import '../../workspace/workspace_tab.dart';
import '../remote_desktop_interaction.dart';
import '../remote_display.dart';
import 'ard_auth.dart';
import 'finder_locator.dart';
import 'move_throttle.dart';
import 'rfb_client.dart';
import 'remote_mac_state.dart';
import 'rfb_isolate_client.dart';
import 'vnc_clipboard_bridge.dart';
import 'vnc_keysym.dart';

/// VNC 会话：内置 RFB 客户端 + 剪贴板同步 + 通过内置 SSH（兼容旧关联）传输文件
class VncSession extends WorkspaceTab implements RemoteDisplay {
  VncSession(super.host, this._hosts, this._connector, this._sshUi, this._vncUi);

  final HostRepository _hosts;
  final SshConnector _connector;
  final SshInteraction _sshUi;
  final RemoteDesktopInteraction _vncUi;

  /// RFB 客户端（协议与解码运行在后台 isolate）
  RfbIsolateClient? client;
  Timer? _clipTimer;
  Timer? _statTimer;

  /// 统计写入日志的间隔
  static const _statInterval = Duration(seconds: 5);

  /// 远程是否锁屏（经关联 SSH 主机查询；未知为 null）。锁屏时画面可能仍显示锁屏前的桌面，但输入由锁屏界面接收
  bool? remoteLocked;
  Timer? _lockTimer;

  /// 锁屏状态检查间隔
  static const _lockInterval = Duration(seconds: 5);

  /// 剪贴板桥：本地与远程之间双向同步文本与文件
  late final clipboard = VncClipboardBridge(
    hasSsh: () => hasSsh,
    connectSsh: prepareTransfer,
    transfers: () => transfers,
    sendRfbText: (t) => client?.sendClipboard(t),
    sendKey: (k, down) => client?.sendKey(k, down),
    isKeyDown: (k) => _downKeys.containsValue(k),
  );

  /// 帧号，每次帧更新递增（UI 据此重绘）
  int frame = 0;

  /// 是否同步剪贴板
  bool get clipboardSync => clipboard.enabled;

  /// 开关剪贴板同步；重新开启时立即推送当前本地剪贴板
  void setClipboardSync(bool on) {
    clipboard.enabled = on;
    AppLog.i('clipboard', '剪贴板同步${on ? '开启' : '关闭'}');
    if (on) unawaited(clipboard.pushLocal());
    notifyListeners();
  }

  SshConnection? _transferConn;
  TransferManager? transfers;

  /// 关联 SSH 主机 uuid（用于文件传输）
  String? get transferHostUuid => host.legacyTransferHost;

  /// 是否可用 SSH（内置 SSH 配置已启用，或旧版关联了独立 SSH 主机）
  bool get hasSsh => host.vncSsh != null || transferHostUuid != null;

  /// 连接
  Future<void> connect() async {
    setState(SessionState.connecting);
    var password = host.savePassword ? host.password : null;
    var username = host.username;
    String? err;
    // 服务器是否要求 macOS 账户认证（需要用户名 + 密码）
    var needUsername = false;
    for (var attempt = 0; attempt < 5; attempt++) {
      final c = RfbIsolateClient();
      AppLog.i(
        'vnc',
        '会话「${host.name}」第 ${attempt + 1} 次连接（用户名${username.isEmpty ? '未填' : '已填'}，'
            '密码${password?.isNotEmpty == true ? '已填' : '未填'}）',
      );
      try {
        await c.connect(host.address, host.port, username: username, password: password);
        client = c;
        _sessionPassword = password;
        _bind(c);
        setState(SessionState.connected);
        unawaited(_hosts.touchConnected(host.uuid));
        return;
      } on RfbPasswordRequired catch (e) {
        c.close();
        needUsername = e.needUsername;
        AppLog.i('vnc', '需要输入凭据（需要用户名：$needUsername）');
      } on RfbAuthException catch (e) {
        c.close();
        err = e.message;
        if (c.securityType == ArdAuth.securityType) needUsername = true;
        AppLog.w('vnc', '认证失败：${e.message}');
      } catch (e, st) {
        c.close();
        AppLog.e('vnc', '连接失败', e, st);
        setState(SessionState.failed, error: '$e');
        return;
      }
      final input = await _vncUi.askDesktopPassword(host, error: err, askUsername: needUsername);
      if (input == null) {
        AppLog.i('vnc', '用户取消输入凭据');
        setState(SessionState.failed, error: 'cancelled');
        return;
      }
      password = input.password;
      final newUser = input.username;
      if (newUser != null && newUser.isNotEmpty && newUser != username) {
        username = newUser;
        await _hosts.updateUsername(host.uuid, newUser);
      }
      if (input.remember) {
        await _hosts.updatePassword(host.uuid, password, true);
      }
      err = 'wrong_password';
    }
    setState(SessionState.failed, error: err);
  }

  void _bind(RfbIsolateClient c) {
    cursor = null;
    clipboard.start();
    // 清理之前遗留在远程的修饰键状态（如上次切走时 ⌘ 未释放），避免点击无法激活窗口等问题
    _downKeys.clear();
    unawaited(_clearStuckModifiers(c));
    remoteLocked = null;
    _lockTimer?.cancel();
    if (hasSsh) {
      unawaited(_checkLock());
      _lockTimer = Timer.periodic(_lockInterval, (_) => unawaited(_checkLock()));
    }
    AppLog.i('vnc', '已连接「${host.name}」${c.width}×${c.height}，安全类型 ${c.securityType}');
    // 协议统计由后台 isolate 写入 vnc.stat；这里定期记录本地输入统计（限流效果）
    _statTimer?.cancel();
    _moves.cancel();
    _statTimer = Timer.periodic(_statInterval, (_) {
      if (_statLocalMoves == 0 && _statScrollSteps == 0) return;
      AppLog.i('vnc.input', '${_statInterval.inSeconds}s：本地鼠标事件 $_statLocalMoves，滚轮 $_statScrollSteps 格');
      _statLocalMoves = _statScrollSteps = 0;
    });
    c.onFrame = () {
      frame++;
      notifyListeners();
    };
    c.onResize = (_, _) => notifyListeners();
    c.onCursor = (cur) {
      cursor = cur;
      notifyListeners();
    };
    c.onClipboard = clipboard.onRemoteText;
    c.onClosed = (e) {
      _clipTimer?.cancel();
      _lockTimer?.cancel();
      clipboard.stop();
      _statTimer?.cancel();
      _moves.cancel();
      if (state == SessionState.connected) {
        setState(SessionState.disconnected, error: e?.toString());
      }
    };
    // 定时检查本地剪贴板：文本变化时推送到远程，文件则记录等待 ⌘V
    _clipTimer = Timer.periodic(const Duration(milliseconds: 1500), (_) => unawaited(clipboard.pushLocal()));
  }

  // ---------- RemoteDisplay ----------

  /// 已按下的物理键 -> keysym（保证抬起时发送相同 keysym）
  final Map<PhysicalKeyboardKey, int> _downKeys = {};

  /// 鼠标移动限流（约 60Hz），见 MoveThrottle
  late final _moves = MoveThrottle((x, y) => client?.sendPointer(x, y, _buttons));

  /// 统计：本地收到的鼠标事件数（与实际发送数对照，体现限流效果）、发送的滚轮格数
  int _statLocalMoves = 0;
  int _statScrollSteps = 0;
  int _buttons = 0;
  int _lastX = 0, _lastY = 0;

  @override
  bool get displayReady => client != null && state == SessionState.connected;

  @override
  int get frameWidth => client?.width ?? 0;

  @override
  int get frameHeight => client?.height ?? 0;

  @override
  FrameUpdate? takeFrame() => client?.takeFrame();

  @override
  RemoteCursor? cursor;

  @override
  void pointerEvent(int x, int y, int buttons) {
    final c = client;
    if (c == null) return;
    _lastX = x;
    _lastY = y;
    _statLocalMoves++;
    if (buttons != _buttons) {
      // 按键状态变化（点击 / 拖动开始结束）立即发送，丢弃尚未发送的移动
      _moves.drop();
      _buttons = buttons;
      c.sendPointer(x, y, buttons, input: true);
      return;
    }
    // 纯移动：限流后只发送最新位置，避免服务器端排队造成滞后
    _moves.move(x, y);
  }

  @override
  void scrollEvent(int x, int y, int steps) {
    // RFB 滚轮：第 4 键向上、第 5 键向下，每格一次“按下 + 抬起”
    final bit = steps < 0 ? 8 : 16;
    // 与 noVNC / TigerVNC 一致：滚轮立即发送，不限流不丢弃（格数已由 ScrollAccumulator 按位移折算）
    final n = steps.abs();
    _statScrollSteps += n;
    if (n == 0) return;
    _moves.flush();
    for (var i = 0; i < n; i++) {
      client?.sendPointer(x, y, _buttons | bit, input: true);
      client?.sendPointer(x, y, _buttons);
    }
  }

  @override
  KeyEventResult keyEvent(KeyEvent e) {
    final c = client;
    if (c == null) return KeyEventResult.ignored;
    // 剪贴板相关快捷键（⌘V 粘贴本地文件、⌘C / ⌘X 后拉取远程剪贴板）
    if (clipboard.handleKey(e)) return KeyEventResult.handled;
    if (e is KeyDownEvent || e is KeyRepeatEvent) {
      final sym = _downKeys[e.physicalKey] ?? VncKeysym.fromEvent(e);
      if (sym == null) return KeyEventResult.ignored;
      _downKeys[e.physicalKey] = sym;
      c.sendKey(sym, true);
      if (e is KeyDownEvent && _modifiers.contains(sym)) AppLog.d('vnc.key', '修饰键按下 ${_hex(sym)}');
      return KeyEventResult.handled;
    }
    if (e is KeyUpEvent) {
      final sym = _downKeys.remove(e.physicalKey) ?? VncKeysym.fromEvent(e);
      if (sym != null) {
        c.sendKey(sym, false);
        if (_modifiers.contains(sym)) AppLog.d('vnc.key', '修饰键松开 ${_hex(sym)}');
      }
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  void displayFocused() => unawaited(clipboard.pushLocal());

  /// 修饰键 keysym：Shift、Control、Meta、Alt、Super（左右）
  static const _modifiers = [0xffe1, 0xffe2, 0xffe3, 0xffe4, 0xffe7, 0xffe8, 0xffe9, 0xffea, 0xffeb, 0xffec];

  @override
  void displayBlurred() {
    final c = client;
    if (c == null) return;
    if (_downKeys.isNotEmpty) {
      AppLog.i('vnc.key', '失去焦点，释放 ${_downKeys.length} 个按键：${_downKeys.values.map(_hex).toList()}');
      for (final sym in _downKeys.values) {
        c.sendKey(sym, false);
      }
      _downKeys.clear();
      // 释放后核对远程状态（仅在已有传输连接时，不主动建立连接）
      final conn = _transferConn;
      if (conn != null && !conn.isClosed) {
        Timer(const Duration(milliseconds: 300), () => RemoteMacState.logModifiers(conn.client, '失去焦点释放后'));
      }
    }
    if (_buttons != 0) {
      AppLog.i('vnc.key', '失去焦点，释放鼠标键 $_buttons');
      _moves.drop();
      _buttons = 0;
      c.sendPointer(_lastX, _lastY, 0);
    }
  }

  static String _hex(int v) => '0x${v.toRadixString(16)}';

  bool _lockChecking = false;

  /// 查询远程锁屏状态，变化时写日志并通知界面
  Future<void> _checkLock() async {
    if (_lockChecking || state != SessionState.connected) return;
    _lockChecking = true;
    try {
      final conn = await prepareTransfer();
      final locked = await RemoteMacState.screenLocked(conn.client);
      if (locked != null && locked != remoteLocked) {
        AppLog.i('vnc', locked ? '远程 Mac 已锁屏（输入由锁屏界面接收）' : '远程 Mac 未锁屏');
        remoteLocked = locked;
        notifyListeners();
      }
    } catch (e) {
      AppLog.d('vnc', '查询远程锁屏状态失败：$e');
    } finally {
      _lockChecking = false;
    }
  }

  /// 本次连接使用的密码（ARD 认证即 macOS 登录密码，仅保存在内存中，用于一键解锁）
  String? _sessionPassword;

  /// 是否可以一键解锁（本次连接用了登录密码）
  bool get canUnlock => (_sessionPassword ?? '').isNotEmpty;

  /// 用保存的登录密码解锁远程锁屏：先移动鼠标与按 Shift 唤醒，再输入密码并回车（密码不写入日志）
  Future<bool> unlock() async {
    final c = client;
    final pass = _sessionPassword ?? '';
    if (c == null || pass.isEmpty) return false;
    AppLog.i('vnc', '尝试解锁远程锁屏（输入 ${pass.length} 个字符 + 回车）');
    c.sendPointer(_lastX + 1, _lastY, 0);
    c.sendKey(0xffe1, true);
    c.sendKey(0xffe1, false);
    await Future.delayed(const Duration(milliseconds: 600));
    for (final r in pass.runes) {
      final sym = VncKeysym.fromChar(r);
      c.sendKey(sym, true);
      c.sendKey(sym, false);
    }
    c.sendKey(VncKeysym.enter, true);
    c.sendKey(VncKeysym.enter, false);
    // 等待登录窗口处理后核对
    await Future.delayed(const Duration(seconds: 2));
    await _checkLock();
    final ok = remoteLocked == false;
    AppLog.i('vnc', '解锁${ok ? '成功' : '后仍为锁屏（密码错误或锁屏界面未接收输入）'}');
    return ok;
  }

  /// 连接后释放全部修饰键；配置了关联 SSH 主机时在释放前后查询远程修饰键状态写入日志，
  /// 释放后仍按下说明卡键并非本客户端造成（如其他会话），需在远程按一下对应键
  Future<void> _clearStuckModifiers(RfbIsolateClient c) async {
    SshConnection? conn;
    if (hasSsh) {
      try {
        conn = await prepareTransfer();
        await RemoteMacState.logModifiers(conn.client, '连接时');
      } catch (_) {}
    }
    for (final m in _modifiers) {
      c.sendKey(m, false);
    }
    AppLog.i('vnc.key', '连接后释放全部修饰键，清理遗留的按键状态');
    if (conn == null) return;
    await Future.delayed(const Duration(milliseconds: 300));
    final left = await RemoteMacState.logModifiers(conn.client, '释放后');
    if (left != null && left.isNotEmpty) {
      AppLog.w('vnc.key', '释放后远程仍有修饰键按下 $left：可能来自其他会话或远程本机，请在远程按一下对应键');
    }
  }

  @override
  void viewResized(int width, int height) {}

  /// 发送 Ctrl+Alt+Del
  void sendCtrlAltDel() {
    final c = client;
    if (c == null) return;
    for (final k in VncKeysym.ctrlAltDel) {
      c.sendKey(k, true);
    }
    for (final k in VncKeysym.ctrlAltDel.reversed) {
      c.sendKey(k, false);
    }
  }

  /// 建立（或复用）关联 SSH 主机的连接与传输队列；拖入文件时提前调用，减少松手后的等待
  Future<SshConnection> prepareTransfer() {
    final c = _transferConn;
    if (c != null && !c.isClosed) return Future.value(c);
    // 并发调用（剪贴板、锁屏检查、上传同时发起）共用同一次连接，避免重复建立 SSH 连接且多余连接不关闭
    return _transferConnecting ??= _connectTransfer().whenComplete(() => _transferConnecting = null);
  }

  Future<SshConnection>? _transferConnecting;

  Future<SshConnection> _connectTransfer() async {
    // 建立连接前读取最新配置；已建立的传输连接在重连 VNC 后更新
    final latest = await _hosts.getByUuid(host.uuid) ?? host;
    final cfg = latest.vncSsh;
    final HostEntry sshHost;
    if (cfg != null) {
      // 内置 SSH：与 VNC 共用地址、用户名、密码；未保存密码时使用本次 VNC 连接输入的密码，避免再次询问
      final base = latest.asSshHost(cfg);
      final pass = (_sessionPassword ?? '').isNotEmpty ? _sessionPassword : null;
      sshHost = pass == null ? base : base.copyWith(password: () => pass, savePassword: true);
    } else {
      final uuid = latest.legacyTransferHost;
      if (uuid == null) throw StateError('no ssh');
      final linked = await _hosts.getByUuid(uuid);
      if (linked == null) {
        AppLog.w('upload', '关联的传输主机不存在 $uuid');
        throw StateError('transfer host not found');
      }
      sshHost = linked;
    }
    AppLog.i('upload', '连接传输主机「${sshHost.name}」${sshHost.endpoint}');
    final conn = await _connector.connect(sshHost, _sshUi);
    _transferConn = conn;
    transfers?.dispose();
    transfers = TransferManager(SftpService(conn.client), autoRemoveDoneAfter: const Duration(seconds: 3));
    notifyListeners();
    return conn;
  }

  /// 通过关联 SSH 主机上传文件，返回实际上传到的远程目录。
  /// 远程为 macOS 时按 Finder 布局确定目标：[remotePoint]（帧缓冲像素坐标）所在的 Finder 窗口文件夹，
  /// 不在任何窗口内则为桌面；[remotePoint] 为空时取最前面的 Finder 窗口。
  /// 远程不是 macOS 时上传到用户主目录；macOS 上无法识别目标时抛出 [FinderLocateException]，不做猜测
  Future<String> uploadFiles(List<String> paths, {Offset? remotePoint}) async {
    final point = remotePoint == null ? '无（按钮选择）' : '(${remotePoint.dx.round()},${remotePoint.dy.round()})';
    AppLog.i('upload', 'VNC 上传 ${paths.length} 项，拖放点 $point，帧缓冲宽 ${client?.width}');
    final conn = await prepareTransfer();
    final r = await FinderLocator.query(conn.client);
    final String dir;
    if (r.layout != null) {
      dir = r.layout!.folderAt(remotePoint, client?.width ?? 0);
    } else if (r.error == 'finder.not_mac') {
      dir = await SftpService(conn.client).home();
      AppLog.i('upload', '远程不是 macOS，上传到主目录');
    } else {
      AppLog.w('upload', '无法确定目标文件夹，取消上传：${r.error} ${r.detail ?? ''}');
      throw FinderLocateException(r.error!, r.detail);
    }
    AppLog.i('upload', '目标目录 $dir');
    for (final p in paths) {
      transfers!.upload(p, dir);
    }
    return dir;
  }

  @override
  Future<void> reconnect() async {
    _clipTimer?.cancel();
    _lockTimer?.cancel();
    clipboard.stop();
    _statTimer?.cancel();
    _moves.cancel();
    client?.close();
    client = null;
    await connect();
  }

  @override
  Future<void> close() async {
    state = SessionState.disconnected;
    _clipTimer?.cancel();
    _lockTimer?.cancel();
    clipboard.stop();
    _statTimer?.cancel();
    _moves.cancel();
    client?.close();
    client = null;
    transfers?.dispose();
    transfers = null;
    _transferConn?.close();
    _transferConn = null;
  }
}
