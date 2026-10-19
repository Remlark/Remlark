import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart' show KeyEventResult;

import '../../sftp/sftp_service.dart';
import '../../sftp/transfer_manager.dart';
import '../../ssh/ssh_connector.dart';
import '../../ssh/ssh_interaction.dart';
import '../../hosts/host_repository.dart';
import '../../workspace/workspace_tab.dart';
import '../remote_desktop_interaction.dart';
import '../remote_display.dart';
import 'rfb_client.dart';
import 'vnc_keysym.dart';

/// VNC 会话：内置 RFB 客户端 + 剪贴板同步 + 通过关联 SSH 主机传输文件
class VncSession extends WorkspaceTab implements RemoteDisplay {
  VncSession(super.host, this._hosts, this._connector, this._sshUi, this._vncUi);

  final HostRepository _hosts;
  final SshConnector _connector;
  final SshInteraction _sshUi;
  final RemoteDesktopInteraction _vncUi;

  RfbClient? client;
  Timer? _clipTimer;
  String? _lastClip;

  /// 帧号，每次帧更新递增（UI 据此重绘）
  int frame = 0;

  /// 是否同步剪贴板
  bool clipboardSync = true;

  SshConnection? _transferConn;
  TransferManager? transfers;

  /// 关联 SSH 主机 uuid（用于文件传输）
  String? get transferHostUuid => host.extra['transferHost'] as String?;

  /// 远程接收目录
  String get transferDir => (host.extra['transferDir'] as String?)?.trim().isNotEmpty == true
      ? host.extra['transferDir'] as String
      : '~/Desktop';

  /// 连接
  Future<void> connect() async {
    setState(SessionState.connecting);
    var password = host.savePassword ? host.password : null;
    String? err;
    for (var attempt = 0; attempt < 5; attempt++) {
      final c = RfbClient();
      try {
        await c.connect(host.address, host.port, password: password);
        client = c;
        _bind(c);
        setState(SessionState.connected);
        unawaited(_hosts.touchConnected(host.uuid));
        return;
      } on RfbPasswordRequired {
        c.close();
      } on RfbAuthException catch (e) {
        c.close();
        err = e.message;
      } catch (e) {
        c.close();
        setState(SessionState.failed, error: '$e');
        return;
      }
      final input = await _vncUi.askDesktopPassword(host, error: err);
      if (input == null) {
        setState(SessionState.failed, error: 'cancelled');
        return;
      }
      password = input.password;
      if (input.remember) {
        await _hosts.updatePassword(host.uuid, password, true);
      }
      err = 'wrong_password';
    }
    setState(SessionState.failed, error: err);
  }

  void _bind(RfbClient c) {
    c.onFrame = () {
      frame++;
      notifyListeners();
    };
    c.onResize = (_, _) => notifyListeners();
    c.onClipboard = (text) {
      if (!clipboardSync) return;
      _lastClip = text;
      Clipboard.setData(ClipboardData(text: text));
    };
    c.onClosed = (e) {
      _clipTimer?.cancel();
      if (state == SessionState.connected) {
        setState(SessionState.disconnected, error: e?.toString());
      }
    };
    // 定时检查本地剪贴板，变化时发送到远程
    _clipTimer = Timer.periodic(const Duration(milliseconds: 1500), (_) => syncClipboard());
  }

  /// 本地剪贴板变化时推送到远程
  Future<void> syncClipboard() async {
    if (!clipboardSync || state != SessionState.connected) return;
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final text = data?.text;
    if (text == null || text == _lastClip) return;
    _lastClip = text;
    client?.sendClipboard(text);
  }

  // ---------- RemoteDisplay ----------

  /// 已按下的物理键 -> keysym（保证抬起时发送相同 keysym）
  final Map<PhysicalKeyboardKey, int> _downKeys = {};
  int _buttons = 0;

  @override
  bool get displayReady => client != null && state == SessionState.connected;

  @override
  int get frameWidth => client?.width ?? 0;

  @override
  int get frameHeight => client?.height ?? 0;

  @override
  Uint8List? readFrame() {
    final c = client;
    return c == null ? null : Uint8List.fromList(c.framebuffer);
  }

  @override
  void pointerEvent(int x, int y, int buttons) {
    _buttons = buttons;
    client?.sendPointer(x, y, buttons);
  }

  @override
  void scrollEvent(int x, int y, double dy) {
    // RFB 滚轮：第 4 键向上、第 5 键向下，按下后立即抬起
    final bit = dy < 0 ? 8 : 16;
    client?.sendPointer(x, y, _buttons | bit);
    client?.sendPointer(x, y, _buttons);
  }

  @override
  KeyEventResult keyEvent(KeyEvent e) {
    final c = client;
    if (c == null) return KeyEventResult.ignored;
    if (e is KeyDownEvent || e is KeyRepeatEvent) {
      final sym = _downKeys[e.physicalKey] ?? VncKeysym.fromEvent(e);
      if (sym == null) return KeyEventResult.ignored;
      _downKeys[e.physicalKey] = sym;
      c.sendKey(sym, true);
      return KeyEventResult.handled;
    }
    if (e is KeyUpEvent) {
      final sym = _downKeys.remove(e.physicalKey) ?? VncKeysym.fromEvent(e);
      if (sym != null) c.sendKey(sym, false);
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  void displayFocused() => syncClipboard();

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

  /// 通过关联 SSH 主机上传文件到远程桌面目录
  Future<void> uploadFiles(List<String> paths) async {
    final uuid = transferHostUuid;
    if (uuid == null) throw StateError('no transfer host');
    if (_transferConn == null || _transferConn!.isClosed) {
      final sshHost = await _hosts.getByUuid(uuid);
      if (sshHost == null) throw StateError('transfer host not found');
      _transferConn = await _connector.connect(sshHost, _sshUi);
      transfers?.dispose();
      transfers = TransferManager(SftpService(_transferConn!.client));
      notifyListeners();
    }
    var dir = transferDir;
    if (dir.startsWith('~')) {
      final home = await SftpService(_transferConn!.client).home();
      dir = '$home${dir.substring(1)}';
    }
    for (final p in paths) {
      transfers!.upload(p, dir);
    }
  }

  @override
  Future<void> reconnect() async {
    _clipTimer?.cancel();
    client?.close();
    client = null;
    await connect();
  }

  @override
  Future<void> close() async {
    state = SessionState.disconnected;
    _clipTimer?.cancel();
    client?.close();
    client = null;
    transfers?.dispose();
    transfers = null;
    _transferConn?.close();
    _transferConn = null;
  }
}
