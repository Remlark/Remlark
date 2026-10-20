import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart' show KeyEventResult;
import 'package:pasteboard/pasteboard.dart';
import 'package:path/path.dart' as p;

import '../../../utils/app_log.dart';
import '../../../utils/platform_utils.dart';
import '../../hosts/host_model.dart';
import '../../hosts/host_repository.dart';
import '../../workspace/workspace_tab.dart';
import '../remote_desktop_interaction.dart';
import '../remote_display.dart';
import 'rdp_client.dart';
import 'rdp_scancode.dart';

/// 一次连接尝试的结果
enum _Attempt { connected, authFailed, certChanged, failed }

/// RDP 会话通知（显示给用户的提示）
/// 需要提示用户的事件（只提示异常；成功时不打扰，进度见状态栏）
enum RdpNotice { filesTooLarge }

/// RDP 会话：内嵌 FreeRDP（通过 FFI 调用原生胶水库），画面在应用内渲染。
/// 负责登录流程（保存的密码 / 弹框输入 / 密码错误重试）、证书指纹校验、
/// 键鼠输入、动态分辨率、剪贴板（文本与文件双向）与共享文件夹传输。
class RdpSession extends WorkspaceTab implements RemoteDisplay {
  RdpSession(super.host, this._hosts, this._ui);

  final HostRepository _hosts;
  final RemoteDesktopInteraction _ui;

  RdpClient? _client;

  /// 原生库是否缺失
  bool libraryMissing = false;

  /// 本地共享文件夹（远程中为 \\tsclient\Remlark）
  String? sharedDir;

  /// 远程文件下载进度（KB）
  int filesDoneKb = 0;
  int filesTotalKb = 0;

  /// 提示回调（UI 显示 SnackBar）：类型与数量
  void Function(RdpNotice notice, int count)? onNotice;

  /// macOS 上把 Command 映射为 Ctrl
  bool metaAsCtrl = Platform.isMacOS;

  String? _fingerprint;
  Timer? _clipTimer;
  Timer? _resizeTimer;
  String? _lastClipText;
  String _lastClipFiles = '';
  int _buttons = 0;
  int _lastX = 0, _lastY = 0;
  Size? _viewSize;
  final Completer<void> _viewSizeKnown = Completer<void>();
  final Set<PhysicalKeyboardKey> _downKeys = {};

  /// 是否跟随窗口大小自动调整分辨率（未配置固定分辨率时）
  bool get _dynamicResolution => host.extra['width'] == null || host.extra['height'] == null;

  /// 连接
  Future<void> connect() async {
    setState(SessionState.connecting);
    if (!RdpClient.isAvailable) {
      libraryMissing = true;
      setState(SessionState.failed, error: 'rdp.lib_missing');
      return;
    }
    sharedDir ??= await _prepareSharedDir();
    _fingerprint = host.hostKeyFingerprint;
    var password = host.savePassword ? host.password : null;
    var remember = false;
    String? error;
    // 等待视图尺寸确定，用作初始分辨率
    await _viewSizeKnown.future.timeout(const Duration(milliseconds: 600), onTimeout: () {});

    for (var attempt = 0; attempt < 5; attempt++) {
      if (password == null || password.isEmpty) {
        final input = await _ui.askDesktopPassword(host, error: error);
        if (input == null) {
          setState(SessionState.failed, error: 'cancelled');
          return;
        }
        password = input.password;
        remember = input.remember;
      }
      AppLog.i('rdp', '连接「${host.name}」${host.endpoint}（第 ${attempt + 1} 次）');
      final (result, detail) = await _attempt(password);
      AppLog.i('rdp', '连接结果 ${result.name}${detail == null ? '' : '：$detail'}');
      switch (result) {
        case _Attempt.connected:
          if (remember) await _hosts.updatePassword(host.uuid, password, true);
          unawaited(_hosts.touchConnected(host.uuid));
          _startClipboardSync();
          return;
        case _Attempt.authFailed:
          error = 'wrong_password';
          password = null;
        case _Attempt.certChanged:
          final ok = await _ui.confirmCertificateChanged(host, _fingerprint ?? '', detail ?? '');
          if (!ok) {
            setState(SessionState.failed, error: 'cancelled');
            return;
          }
          _fingerprint = detail;
          await _hosts.updateFingerprint(host.uuid, detail ?? '');
        case _Attempt.failed:
          setState(SessionState.failed, error: detail);
          return;
      }
    }
    setState(SessionState.failed, error: 'wrong_password');
  }

  /// 进行一次连接，返回结果与附加信息（错误描述或新证书指纹）
  Future<(_Attempt, String?)> _attempt(String password) async {
    _disposeClient();
    final c = RdpClient();
    _client = c;
    final done = Completer<(_Attempt, String?)>();
    String? changedFp;
    var authFailed = false;

    c.onCertificate = (changed, fp) {
      if (changed) {
        changedFp = fp;
      } else {
        // 首次连接记录指纹
        _fingerprint = fp;
        unawaited(_hosts.updateFingerprint(host.uuid, fp));
      }
    };
    c.onAuthFailed = (_) => authFailed = true;
    c.onConnected = (w, h) {
      setState(SessionState.connected);
      if (!done.isCompleted) done.complete((_Attempt.connected, null));
    };
    c.onFrame = notifyListeners;
    c.onResize = (_, _) => notifyListeners();
    c.onDisconnected = (code, msg) {
      if (!done.isCompleted) {
        if (changedFp != null) {
          done.complete((_Attempt.certChanged, changedFp));
        } else if (authFailed) {
          done.complete((_Attempt.authFailed, null));
        } else {
          done.complete((_Attempt.failed, msg ?? 'error $code'));
        }
        return;
      }
      // 已连接后断开
      _clipTimer?.cancel();
      if (state == SessionState.connected) {
        setState(SessionState.disconnected, error: code == 0 ? null : msg);
      }
    };
    c.onClipboardText = (text) {
      _lastClipText = text;
      Clipboard.setData(ClipboardData(text: text));
    };
    c.onClipboardFiles = (paths) async {
      _lastClipFiles = paths.join('\n');
      filesDoneKb = filesTotalKb = 0;
      await Pasteboard.writeFiles(paths);
      notifyListeners();
    };
    c.onClipboardFilesSkipped = (count, mb) => onNotice?.call(RdpNotice.filesTooLarge, mb);
    c.onClipboardFilesProgress = (done, total) {
      filesDoneKb = done;
      filesTotalKb = total;
      notifyListeners();
    };
    c.onClipboardReady = (ok) {
      final r = _clipReady;
      _clipReady = null;
      if (r != null && !r.isCompleted) r.complete(ok);
    };

    final size = _viewSize;
    final fixedW = (host.extra['width'] as num?)?.toInt();
    final fixedH = (host.extra['height'] as num?)?.toInt();
    final proxy = host.proxy;
    c.connect(
      RdpConnectOptions(
        host: host.address,
        port: host.port,
        username: host.username,
        password: password,
        domain: host.extra['domain'] as String? ?? '',
        width: fixedW ?? size?.width.floor() ?? 1280,
        height: fixedH ?? size?.height.floor() ?? 800,
        sharedDir: sharedDir,
        clipboard: host.extra['clipboard'] != false,
        knownFingerprint: _fingerprint,
        tempDir: (await PlatformUtils.dataDir()).path,
        proxyType: proxy.enabled ? (proxy.type == ProxyType.http ? 1 : 2) : 0,
        proxyHost: proxy.host,
        proxyPort: proxy.port,
        proxyUser: proxy.username,
        proxyPassword: proxy.password ?? '',
      ),
    );
    return done.future;
  }

  /// 准备共享目录：<数据目录>/rdp_transfer/<主机名>
  Future<String> _prepareSharedDir() async {
    final base = await PlatformUtils.dataDir();
    final safe = host.name.replaceAll(RegExp(r'[^\w\-. ]'), '_');
    final dir = Directory(p.join(base.path, 'rdp_transfer', safe));
    if (!dir.existsSync()) dir.createSync(recursive: true);
    return dir.path;
  }

  // ---------- 剪贴板 ----------

  /// 定时检查本地剪贴板，变化时同步到远程（文件优先于文本）
  void _startClipboardSync() {
    _clipTimer?.cancel();
    if (host.extra['clipboard'] == false) return;
    _clipTimer = Timer.periodic(const Duration(milliseconds: 1200), (_) => syncClipboard());
  }

  /// 立即检查本地剪贴板
  Future<void> syncClipboard() async {
    final c = _client;
    if (c == null || state != SessionState.connected || host.extra['clipboard'] == false) return;
    List<String> files = const [];
    try {
      files = await Pasteboard.files();
    } catch (_) {}
    if (files.isNotEmpty) {
      final key = files.join('\n');
      if (key != _lastClipFiles) {
        _lastClipFiles = key;
        c.setClipboardFiles(files);
      }
      return;
    }
    _lastClipFiles = '';
    final text = (await Clipboard.getData(Clipboard.kTextPlain))?.text;
    if (text == null || text == _lastClipText) return;
    _lastClipText = text;
    c.setClipboardText(text);
  }

  // ---------- 文件传输 ----------

  /// 等待服务端确认本地剪贴板（拖放后粘贴前使用）
  Completer<bool>? _clipReady;

  /// 拖入的文件：复制到共享文件夹，同时放入远程剪贴板。
  /// [at] 为松手处的远程坐标：服务端确认剪贴板后，在该处点击激活窗口（资源管理器 / 桌面）并发送 Ctrl+V，
  /// 文件直接粘贴到松手处的文件夹。RDP 无法查询远程窗口与文件夹，只能借助“激活 + 粘贴”实现
  Future<int> dropFiles(List<String> paths, {(int, int)? at}) async {
    final dir = sharedDir ?? await _prepareSharedDir();
    sharedDir = dir;
    for (final src in paths) {
      final dst = p.join(dir, p.basename(src));
      final type = FileSystemEntity.typeSync(src);
      if (type == FileSystemEntityType.directory) {
        await _copyDir(Directory(src), Directory(dst));
      } else if (type == FileSystemEntityType.file) {
        await File(src).copy(dst);
      }
    }
    _lastClipFiles = paths.join('\n');
    final ready = _clipReady = Completer<bool>();
    _client?.setClipboardFiles(paths);
    var pasted = false;
    if (at != null) {
      // 服务端确认新剪贴板后再粘贴，否则可能粘贴出旧内容；超时则只提示手动粘贴
      pasted = await ready.future.timeout(const Duration(seconds: 2), onTimeout: () => false);
      if (pasted) await _pasteAt(at.$1, at.$2);
    }
    AppLog.i('rdp', '拖入 ${paths.length} 项：已放入共享目录 $dir 并写入远程剪贴板${pasted ? '，已在 $at 粘贴' : ''}');
    return paths.length;
  }

  /// 在远程 (x, y) 处单击激活窗口，再发送 Ctrl+V
  Future<void> _pasteAt(int x, int y) async {
    final c = _client;
    if (c == null) return;
    _lastX = x;
    _lastY = y;
    c.sendMouse(RdpPointer.move, x, y);
    c.sendMouse(RdpPointer.button1 | RdpPointer.down, x, y);
    c.sendMouse(RdpPointer.button1, x, y);
    // 等窗口激活后再粘贴
    await Future.delayed(const Duration(milliseconds: 150));
    sendCombo([RdpScancode.ctrlLeft, RdpScancode.keyV]);
  }

  Future<void> _copyDir(Directory src, Directory dst) async {
    await dst.create(recursive: true);
    await for (final e in src.list(followLinks: false)) {
      final target = p.join(dst.path, p.basename(e.path));
      if (e is Directory) {
        await _copyDir(e, Directory(target));
      } else if (e is File) {
        await e.copy(target);
      }
    }
  }

  /// 在系统文件管理器中打开共享目录
  Future<void> openSharedDir() async {
    final d = sharedDir ?? await _prepareSharedDir();
    sharedDir = d;
    await PlatformUtils.openInFileManager(d);
  }

  // ---------- 特殊按键 ----------

  /// 发送组合键（按下后逆序抬起）
  void sendCombo(List<int> scancodes) {
    final c = _client;
    if (c == null) return;
    for (final s in scancodes) {
      c.sendKey(s, true);
    }
    for (final s in scancodes.reversed) {
      c.sendKey(s, false);
    }
  }

  /// Ctrl+Alt+Del
  void sendCtrlAltDel() => sendCombo([RdpScancode.ctrlLeft, RdpScancode.altLeft, RdpScancode.delete]);

  /// Windows 键
  void sendWinKey() => sendCombo([RdpScancode.winLeft]);

  // ---------- RemoteDisplay ----------

  @override
  bool get displayReady => _client != null && state == SessionState.connected;

  @override
  int get frameWidth => _client?.width ?? 0;

  @override
  int get frameHeight => _client?.height ?? 0;

  @override
  FrameUpdate? takeFrame() => _client?.takeFrame();

  /// 远程指针形状暂未同步，使用系统指针
  @override
  RemoteCursor? get cursor => null;

  @override
  void pointerEvent(int x, int y, int buttons) {
    _lastX = x;
    _lastY = y;
    final c = _client;
    if (c == null) return;
    final changed = buttons ^ _buttons;
    if (changed == 0) {
      c.sendMouse(RdpPointer.move, x, y);
      return;
    }
    // 按键状态变化：分别发送按下 / 抬起
    for (final (bit, flag) in const [(1, RdpPointer.button1), (4, RdpPointer.button2), (2, RdpPointer.button3)]) {
      if (changed & bit == 0) continue;
      c.sendMouse(flag | (buttons & bit != 0 ? RdpPointer.down : 0), x, y);
    }
    _buttons = buttons;
  }

  @override
  void scrollEvent(int x, int y, int steps) {
    // 滚轮每格 120；向下为负，使用 9 位补码表示；每格发送一次
    final flags = steps < 0 ? (RdpPointer.wheel | 0x78) : (RdpPointer.wheel | RdpPointer.wheelNegative | 0x88);
    for (var i = 0; i < steps.abs(); i++) {
      _client?.sendMouse(flags, x, y);
    }
  }

  @override
  KeyEventResult keyEvent(KeyEvent e) {
    final c = _client;
    if (c == null) return KeyEventResult.ignored;
    final sc = RdpScancode.fromKey(e.physicalKey, metaAsCtrl: metaAsCtrl);
    if (e is KeyDownEvent || e is KeyRepeatEvent) {
      if (sc != null) {
        _downKeys.add(e.physicalKey);
        c.sendKey(sc, true, repeat: e is KeyRepeatEvent);
      } else if (e.character != null && e.character!.isNotEmpty) {
        // 无法映射为扫描码的字符（如输入法）按 Unicode 发送
        for (final r in e.character!.runes) {
          c.sendUnicode(r, true);
          c.sendUnicode(r, false);
        }
      }
      return KeyEventResult.handled;
    }
    if (e is KeyUpEvent) {
      if (sc != null && _downKeys.remove(e.physicalKey)) c.sendKey(sc, false);
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  void displayFocused() => syncClipboard();

  @override
  void displayBlurred() {
    final c = _client;
    if (c == null) return;
    if (_downKeys.isNotEmpty) {
      AppLog.i('rdp', '失去焦点，释放 ${_downKeys.length} 个按键');
      for (final k in _downKeys) {
        final sc = RdpScancode.fromKey(k, metaAsCtrl: metaAsCtrl);
        if (sc != null) c.sendKey(sc, false);
      }
      _downKeys.clear();
    }
    if (_buttons != 0) pointerEvent(_lastX, _lastY, 0);
  }

  @override
  void viewResized(int width, int height) {
    _viewSize = Size(width.toDouble(), height.toDouble());
    if (!_viewSizeKnown.isCompleted) _viewSizeKnown.complete();
    if (!_dynamicResolution || state != SessionState.connected) return;
    // 窗口拖动过程中合并请求
    _resizeTimer?.cancel();
    _resizeTimer = Timer(const Duration(milliseconds: 500), () => _client?.resize(width, height));
  }

  // ---------- 生命周期 ----------

  void _disposeClient() {
    final c = _client;
    _client = null;
    if (c == null) return;
    c.disconnect();
    c.dispose();
  }

  @override
  Future<void> reconnect() async {
    _clipTimer?.cancel();
    _disposeClient();
    await connect();
  }

  @override
  Future<void> close() async {
    state = SessionState.disconnected;
    _clipTimer?.cancel();
    _resizeTimer?.cancel();
    _disposeClient();
  }
}
