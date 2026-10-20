import '../terminal/terminal_session.dart';
import '../workspace/workspace_tab.dart';

/// SFTP 工作区标签：与对应的 SSH 终端会话共用同一连接与传输队列。
/// 关闭 SFTP 标签不会断开 SSH；终端关闭时由工作区一并关闭该标签
class SftpTab extends WorkspaceTab {
  SftpTab(this.session) : super(session.host) {
    _syncState();
    session.addListener(_onSessionChanged);
  }

  /// 所属 SSH 会话
  final TerminalSession session;

  /// 本地栏当前目录（切换标签后保持）
  String? localPath;

  @override
  String get kindLabel => 'SFTP';

  /// 远程栏当前目录：与终端的“最近浏览目录”共用，拖拽上传默认使用该目录
  String? get remotePath => session.lastRemoteDir;
  set remotePath(String? v) => session.lastRemoteDir = v;

  void _syncState() {
    state = session.state;
    error = session.error;
    connectedAt = session.connectedAt;
  }

  void _onSessionChanged() {
    _syncState();
    notifyListeners();
  }

  @override
  Future<void> reconnect() => session.reconnect();

  @override
  Future<void> close() async {
    session.removeListener(_onSessionChanged);
  }

  @override
  void dispose() {
    session.removeListener(_onSessionChanged);
    super.dispose();
  }
}
