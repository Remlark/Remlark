import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:dartssh2/dartssh2.dart';
import 'package:xterm/xterm.dart';

import '../../utils/app_log.dart';
import '../sftp/sftp_service.dart';
import '../sftp/transfer_manager.dart';
import '../ssh/ssh_connector.dart';
import '../ssh/ssh_interaction.dart';
import '../workspace/workspace_tab.dart';
import 'reflow_safe_terminal.dart';

/// SSH 终端会话：持有连接、shell、xterm 终端模型与 SFTP 传输
class TerminalSession extends WorkspaceTab {
  TerminalSession(super.host, this._connector, this._interaction) {
    terminal.onOutput = _handleInput;
    terminal.onResize = (w, h, pw, ph) {
      _cols = w;
      _rows = h;
      AppLog.d('terminal', '「${host.name}」终端尺寸 $w×$h');
      _shell?.resizeTerminal(w, h, pw, ph);
    };
    terminal.onTitleChange = (t) {
      _remoteTitle = t;
      notifyListeners();
    };
  }

  final SshConnector _connector;
  final SshInteraction _interaction;

  /// xterm 终端模型（修正 reflow 后光标漂移）
  final Terminal terminal = ReflowSafeTerminal(maxLines: 20000);

  /// 选区控制器（复制使用）
  final TerminalController controller = TerminalController();

  SshConnection? _conn;
  SSHSession? _shell;
  SftpService? _sftp;
  TransferManager? _transfers;
  TransferManager? _uploads;
  StreamSubscription<String>? _stdoutSub;
  int _cols = 80;
  int _rows = 24;
  String? _remoteTitle;

  /// 广播回调：用户在本终端输入时，由工作区转发给其他选中的会话
  void Function(TerminalSession from, String data)? onUserInput;

  final _outputCtl = StreamController<String>.broadcast();
  final _userInputCtl = StreamController<String>.broadcast();

  /// shell 输出（解码后的原始文本，含控制序列），供 AI 读取终端结果
  Stream<String> get output => _outputCtl.stream;

  /// 用户在本终端的键盘输入（不含程序通过 [sendRaw] 发送的内容）
  Stream<String> get userInput => _userInputCtl.stream;

  /// SFTP 上次浏览的目录（拖拽 / 粘贴上传的默认目标）
  String? lastRemoteDir;

  /// 当前 SSH 连接
  SshConnection? get connection => _conn;

  @override
  String get title => host.name;

  /// 远程设置的终端标题
  String? get remoteTitle => _remoteTitle;

  /// SFTP 服务（连接后可用）
  SftpService? get sftp => _sftp;

  /// SFTP 标签的传输管理器（连接后可用）
  TransferManager? get transfers => _transfers;

  /// 终端拖拽 / 粘贴上传的传输管理器（连接后可用）：与 SFTP 标签的队列分开，
  /// 进度只显示在终端状态栏；成功的任务几秒后自动移除
  TransferManager? get uploads => _uploads;

  /// 建立连接并打开 shell
  Future<void> connect() async {
    setState(SessionState.connecting);
    try {
      final conn = await _connector.connect(
        host,
        _ProgressInteraction(this, _interaction),
      );
      _conn = conn;
      final shell = await conn.client.shell(
        pty: SSHPtyConfig(type: 'xterm-256color', width: _cols, height: _rows),
      );
      AppLog.i('terminal', '「${host.name}」shell 已打开，终端 $_cols×$_rows');
      _shell = shell;
      _sftp = SftpService(conn.client);
      _transfers?.dispose();
      _transfers = TransferManager(_sftp!);
      _uploads?.dispose();
      _uploads = TransferManager(
        _sftp!,
        autoRemoveDoneAfter: const Duration(seconds: 3),
      );
      _stdoutSub = const Utf8Decoder(allowMalformed: true)
          .bind(_mergeOutput(shell))
          .listen((s) {
            terminal.write(s);
            _outputCtl.add(s);
          });
      shell.done.then((_) => _onClosed(null));
      conn.client.done.then(
        (_) => _onClosed(null),
        onError: (Object e) => _onClosed('$e'),
      );
      progress = null;
      setState(SessionState.connected);
      unawaited(_refreshDetectedOs(conn));
    } on ConnectCancelled {
      progress = null;
      setState(SessionState.failed, error: 'cancelled');
    } catch (e) {
      progress = null;
      terminal.write('\r\n\x1b[31m$e\x1b[0m\r\n');
      setState(SessionState.failed, error: '$e');
    }
  }

  /// SSH 探测完成后更新当前标签快照，让已打开的标签立即显示真实系统图标。
  Future<void> _refreshDetectedOs(SshConnection conn) async {
    try {
      final info = await _connector.detectOs(conn);
      if (info == null) return;
      host = host.copyWith(osId: () => info.id, osName: () => info.name);
      notifyListeners();
    } catch (_) {
      // 系统探测失败不影响已建立的终端连接。
    }
  }

  /// 合并 stdout 与 stderr
  Stream<Uint8List> _mergeOutput(SSHSession s) {
    final c = StreamController<Uint8List>();
    var open = 2;
    void done() {
      if (--open == 0) c.close();
    }

    s.stdout.listen(c.add, onDone: done, onError: (_) => done());
    s.stderr.listen(c.add, onDone: done, onError: (_) => done());
    return c.stream;
  }

  void _onClosed(String? reason) {
    if (state == SessionState.disconnected) return;
    if (state != SessionState.connected) return;
    AppLog.i(
      'terminal',
      '「${host.name}」连接断开${reason == null ? '' : '：$reason'}',
    );
    terminal.write('\r\n\x1b[33m[disconnected]\x1b[0m\r\n');
    setState(SessionState.disconnected, error: reason);
  }

  /// 终端用户输入：发往 shell，并触发广播
  void _handleInput(String data) {
    sendRaw(data);
    _userInputCtl.add(data);
    onUserInput?.call(this, data);
  }

  /// 向 shell 发送原始数据（快捷指令、广播、AI 命令均使用）
  void sendRaw(String data) {
    final shell = _shell;
    if (shell == null || state != SessionState.connected) return;
    shell.write(Uint8List.fromList(utf8.encode(data)));
  }

  /// 以粘贴方式输入文本（支持 bracketed paste）
  void pasteText(String text) {
    terminal.paste(text);
  }

  /// 当前选中的文本
  String? selectedText() {
    final sel = controller.selection;
    if (sel == null) return null;
    final t = terminal.buffer.getText(sel);
    return t.isEmpty ? null : t;
  }

  /// 终端最近 [lines] 行文本（供 AI 作为上下文）
  String recentText({int lines = 80}) {
    final buf = terminal.buffer;
    final total = buf.lines.length;
    final start = total - lines < 0 ? 0 : total - lines;
    final sb = StringBuffer();
    for (var i = start; i < total; i++) {
      sb.writeln(buf.lines[i].getText().trimRight());
    }
    return sb.toString().trim();
  }

  /// 通知 UI 刷新
  void refresh() => notifyListeners();

  /// 恢复后续输出的默认文字格式，保留历史、光标和正在接收的控制序列。
  void resetTextStyle() {
    // 直接重置本地模型，避免插入 ANSI 字节破坏分包序列或向远端发送命令。
    terminal.resetCursorStyle();
  }

  @override
  Future<void> reconnect() async {
    _teardown();
    terminal.write('\r\n\x1b[36m[reconnecting...]\x1b[0m\r\n');
    await connect();
  }

  void _teardown() {
    _stdoutSub?.cancel();
    _stdoutSub = null;
    _shell?.close();
    _shell = null;
    _sftp?.close();
    _sftp = null;
    _conn?.close();
    _conn = null;
  }

  @override
  Future<void> close() async {
    state = SessionState.disconnected;
    _teardown();
    _transfers?.dispose();
    _transfers = null;
    _uploads?.dispose();
    _uploads = null;
  }

  @override
  void dispose() {
    _outputCtl.close();
    _userInputCtl.close();
    super.dispose();
  }
}

/// 包装交互接口，把连接进度写入会话
class _ProgressInteraction extends SshInteraction {
  _ProgressInteraction(this._session, this._inner);

  final TerminalSession _session;
  final SshInteraction _inner;

  @override
  void onProgress(String message) {
    _session.progress = message;
    _session.terminal.write('\x1b[90m→ $message\x1b[0m\r\n');
    _session.refresh();
  }

  @override
  Future<PasswordInput?> askPassword(host, {String? error}) =>
      _inner.askPassword(host, error: error);

  @override
  Future<String?> askPassphrase(host, {String? error}) =>
      _inner.askPassphrase(host, error: error);

  @override
  Future<bool> confirmHostKeyChanged(
    host,
    String keyType,
    String oldFingerprint,
    String newFingerprint,
  ) => _inner.confirmHostKeyChanged(
    host,
    keyType,
    oldFingerprint,
    newFingerprint,
  );

  @override
  Future<List<String>?> keyboardInteractive(host, SSHUserInfoRequest request) =>
      _inner.keyboardInteractive(host, request);
}
