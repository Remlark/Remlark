import 'package:flutter/foundation.dart';

import '../sftp/sftp_tab.dart';
import '../remote_desktop/remote_display.dart';
import '../terminal/terminal_session.dart';
import 'workspace_tab.dart';

/// 工作区控制器：管理所有打开的会话标签、当前标签、广播分组与 SFTP 标签
class WorkspaceController extends ChangeNotifier {
  /// 广播目标上限：限制一次同步输入的终端数量
  static const maxBroadcast = 9;

  final List<WorkspaceTab> tabs = [];
  String? activeId;

  /// 普通网格与输入广播分别管理，广播期间锁定布局。
  static const maxGrid = 9;
  bool gridEnabled = false;
  final List<String> gridIds = [];
  String? focusedGridId;

  /// 可以加入网格的会话（文件管理标签不参与）。
  List<WorkspaceTab> get gridCandidates =>
      tabs.where((t) => t is TerminalSession || t is RemoteDisplay).toList();

  /// 网格按用户选择的顺序排列，聚焦期间保留此顺序。
  List<WorkspaceTab> get gridSessions => [
    for (final id in gridIds) ...gridCandidates.where((t) => t.id == id),
  ];
  bool get showingGrid => gridEnabled && focusedGridId == null;

  /// 应用网格选择；广播时禁止更改布局，过滤已关闭或不支持的会话。
  bool showGrid([Iterable<String>? ids]) {
    if (broadcast) return false;
    final valid = gridCandidates.map((t) => t.id).toSet();
    final selected = (ids ?? (gridIds.isEmpty ? valid : gridIds))
        .where(valid.contains)
        .toSet()
        .take(maxGrid)
        .toList();
    if (selected.isEmpty) return false;
    gridIds
      ..clear()
      ..addAll(selected);
    gridEnabled = true;
    focusedGridId = null;
    if (!gridIds.contains(activeId)) activeId = gridIds.first;
    notifyListeners();
    return true;
  }

  /// 切回普通单窗口；保存网格选择，以便以后恢复。
  void showSingle() {
    if (broadcast) return;
    gridEnabled = false;
    focusedGridId = null;
    notifyListeners();
  }

  /// 临时聚焦网格中的一个会话，不关闭其他连接。
  void focusGridSession(String id) {
    if (broadcast || !gridEnabled || !gridIds.contains(id)) return;
    activeId = id;
    focusedGridId = id;
    notifyListeners();
  }

  /// 恢复聚焦前的网格；广播期间不可操作。
  void returnToGrid() {
    if (!gridEnabled) return;
    showGrid();
  }

  /// 标签栏切换：网格内只改变输入焦点，网格外的标签临时全页展示。
  void selectTab(String id) {
    if (!tabs.any((t) => t.id == id)) return;
    if (broadcast &&
        gridEnabled &&
        (focusedGridId != null ? focusedGridId != id : !gridIds.contains(id))) {
      return;
    }
    if (!broadcast &&
        gridEnabled &&
        (focusedGridId != null || !gridIds.contains(id))) {
      focusedGridId = id;
    }
    activate(id);
  }

  /// 广播模式只同步选中 SSH 的输入，不改变当前布局。
  bool broadcast = false;

  /// 广播分组内的终端 id（独立于网格选择）
  final List<String> broadcastIds = [];

  WorkspaceTab? get active {
    for (final t in tabs) {
      if (t.id == activeId) return t;
    }
    return tabs.isEmpty ? null : tabs.last;
  }

  /// 所有终端标签
  List<TerminalSession> get terminals =>
      tabs.whereType<TerminalSession>().toList();

  /// 广播分组内的终端（按加入顺序）
  List<TerminalSession> get broadcastSessions => [
    for (final id in broadcastIds) ...terminals.where((t) => t.id == id),
  ];

  /// 广播分组是否已满
  bool get broadcastFull => broadcastIds.length >= maxBroadcast;

  /// 添加标签并激活
  void add(WorkspaceTab tab) {
    tabs.add(tab);
    if (!broadcast || !gridEnabled) {
      activeId = tab.id;
      if (gridEnabled) {
        if ((tab is TerminalSession || tab is RemoteDisplay) &&
            gridIds.length < maxGrid &&
            focusedGridId == null) {
          gridIds.add(tab.id);
        } else {
          focusedGridId = tab.id;
        }
      }
    }
    if (tab is TerminalSession) {
      tab.onUserInput = _onTerminalInput;
    }
    tab.addListener(notifyListeners);
    notifyListeners();
  }

  /// 激活标签
  void activate(String id) {
    if (!tabs.any((t) => t.id == id) || activeId == id) return;
    activeId = id;
    notifyListeners();
  }

  /// 关闭标签；关闭终端时一并关闭其 SFTP 标签（共用同一 SSH 连接）
  Future<void> closeTab(WorkspaceTab tab) async {
    if (!tabs.contains(tab)) return;
    if (tab is TerminalSession) {
      for (final s
          in tabs
              .whereType<SftpTab>()
              .where((s) => s.session == tab)
              .toList()) {
        await closeTab(s);
      }
    }
    tabs.remove(tab);
    broadcastIds.remove(tab.id);
    gridIds.remove(tab.id);
    if (focusedGridId == tab.id) focusedGridId = null;
    if (gridIds.isEmpty) {
      gridEnabled = false;
      focusedGridId = null;
    }
    if (broadcastIds.isEmpty) broadcast = false;
    tab.removeListener(notifyListeners);
    if (activeId == tab.id) {
      activeId = showingGrid && gridIds.isNotEmpty
          ? gridIds.first
          : (tabs.isEmpty ? null : tabs.last.id);
    }
    if (tabs.isEmpty) broadcast = false;
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

  /// 打开（或激活已有的）SSH 会话对应的 SFTP 标签
  SftpTab openSftp(TerminalSession session) {
    for (final t in tabs.whereType<SftpTab>()) {
      if (t.session == session) {
        selectTab(t.id);
        return t;
      }
    }
    final tab = SftpTab(session);
    // 插入到对应终端标签之后，便于识别归属
    final at = tabs.indexOf(session);
    tabs.insert(at < 0 ? tabs.length : at + 1, tab);
    tab.addListener(notifyListeners);
    if (!broadcast || !gridEnabled) {
      activeId = tab.id;
      if (gridEnabled) focusedGridId = tab.id;
    }
    notifyListeners();
    return tab;
  }

  /// 开启或更新广播目标，只接受 SSH；不改变布局或自动吸收新会话。
  bool startBroadcast({Iterable<String>? ids}) {
    final valid = terminals.map((t) => t.id).toSet();
    final selected = (ids ?? valid)
        .where(valid.contains)
        .toSet()
        .take(maxBroadcast)
        .toList();
    if (selected.isEmpty) return false;
    broadcastIds
      ..clear()
      ..addAll(selected);
    broadcast = true;
    notifyListeners();
    return true;
  }

  /// 关闭广播，保留现有布局与焦点
  void stopBroadcast() {
    broadcast = false;
    broadcastIds.clear();
    notifyListeners();
  }

  /// 把终端加入广播分组；分组已满时返回 false
  bool addToBroadcast(String id) {
    if (!terminals.any((t) => t.id == id)) return false;
    if (broadcastIds.contains(id)) return true;
    if (broadcastFull) return false;
    broadcastIds.add(id);
    notifyListeners();
    return true;
  }

  /// 把终端移出广播分组（会话保持打开，可在标签页中继续使用）
  void removeFromBroadcast(String id) {
    if (broadcastIds.remove(id)) {
      if (broadcastIds.isEmpty) broadcast = false;
      notifyListeners();
    }
  }

  /// 终端输入广播到分组内的其他终端
  void _onTerminalInput(TerminalSession from, String data) {
    if (!broadcast || !broadcastIds.contains(from.id)) return;
    for (final t in broadcastSessions) {
      if (t.id != from.id) t.sendRaw(data);
    }
  }
}
