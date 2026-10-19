import 'package:flutter/foundation.dart';

import '../terminal/terminal_session.dart';
import 'workspace_tab.dart';

/// 工作区控制器：管理所有打开的会话标签、当前标签、平铺模式与广播输入
class WorkspaceController extends ChangeNotifier {
  final List<WorkspaceTab> tabs = [];
  String? activeId;

  /// 平铺模式：同时查看多个终端
  bool tiled = false;

  /// 广播输入开启时，接收输入的终端 id 集合
  final Set<String> broadcastTargets = {};
  bool broadcast = false;

  WorkspaceTab? get active {
    for (final t in tabs) {
      if (t.id == activeId) return t;
    }
    return tabs.isEmpty ? null : tabs.last;
  }

  /// 所有终端标签
  List<TerminalSession> get terminals => tabs.whereType<TerminalSession>().toList();

  /// 添加标签并激活
  void add(WorkspaceTab tab) {
    tabs.add(tab);
    activeId = tab.id;
    if (tab is TerminalSession) {
      tab.onUserInput = _onTerminalInput;
    }
    tab.addListener(notifyListeners);
    notifyListeners();
  }

  /// 激活标签
  void activate(String id) {
    activeId = id;
    notifyListeners();
  }

  /// 关闭标签
  Future<void> closeTab(WorkspaceTab tab) async {
    tabs.remove(tab);
    broadcastTargets.remove(tab.id);
    tab.removeListener(notifyListeners);
    if (activeId == tab.id) activeId = tabs.isEmpty ? null : tabs.last.id;
    notifyListeners();
    await tab.close();
    // 释放界面附加状态中的控制器（如 AI 聊天）
    for (final v in tab.uiState.values) {
      if (v is ChangeNotifier) v.dispose();
    }
    tab.dispose();
  }

  /// 关闭全部标签
  Future<void> closeAll() async {
    for (final t in List.of(tabs)) {
      await closeTab(t);
    }
  }

  void setTiled(bool v) {
    tiled = v;
    notifyListeners();
  }

  /// 开关广播；开启时默认选中全部终端
  void setBroadcast(bool v) {
    broadcast = v;
    if (v && broadcastTargets.isEmpty) {
      broadcastTargets.addAll(terminals.map((t) => t.id));
    }
    notifyListeners();
  }

  /// 切换某终端是否接收广播
  void toggleBroadcastTarget(String id) {
    if (!broadcastTargets.remove(id)) broadcastTargets.add(id);
    notifyListeners();
  }

  /// 终端输入广播到其他选中的终端
  void _onTerminalInput(TerminalSession from, String data) {
    if (!broadcast || !broadcastTargets.contains(from.id)) return;
    for (final t in terminals) {
      if (t.id != from.id && broadcastTargets.contains(t.id)) t.sendRaw(data);
    }
  }
}
