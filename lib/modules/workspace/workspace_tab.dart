import 'package:flutter/foundation.dart';

import '../hosts/host_model.dart';

/// 会话状态
enum SessionState { connecting, connected, disconnected, failed }

/// 工作区标签页的抽象：终端（SSH）、VNC、RDP 会话都实现该接口，
/// 由工作区统一管理标签、关闭与状态显示
abstract class WorkspaceTab extends ChangeNotifier {
  WorkspaceTab(this.host);

  /// 会话对应的主机
  final HostEntry host;

  /// 唯一 id
  final String id = 'tab${_nextId++}';

  static int _nextId = 1;

  SessionState state = SessionState.connecting;

  /// 失败或断开原因
  String? error;

  /// 标签标题
  String get title => host.name;

  /// 进度提示（例如正在连接的跳板名）
  String? progress;

  /// UI 附加状态（如侧边面板、聊天控制器），由界面层存取
  final Map<String, Object?> uiState = {};

  /// 关闭会话并释放资源
  Future<void> close();

  /// 重新连接
  Future<void> reconnect();

  /// 修改状态并通知
  void setState(SessionState s, {String? error}) {
    state = s;
    this.error = error;
    notifyListeners();
  }
}
