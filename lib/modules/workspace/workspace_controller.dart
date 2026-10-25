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

  /// 开始页是独立的展示状态，不占用会话标签，也不修改网格或广播选择。
  bool _startPageRequested = false;
  bool get showingStartPage => tabs.isEmpty || _startPageRequested;

  /// 新建会话进入完整主机选择页，保留当前连接与布局。
  void showStartPage() {
    _startPageRequested = true;
    notifyListeners();
  }

  /// 返回原会话画布；广播期间仍展示原有广播网格。
  void resumeSessions() {
    if (!_startPageRequested) return;
    _startPageRequested = false;
    notifyListeners();
  }

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

  /// 当前是否以网格展示：广播期间固定为网格，与用户选择的布局无关
  bool get showingGrid => broadcast || (gridEnabled && focusedGridId == null);

  /// 当前网格中展示的会话：广播时为广播目标，否则为普通网格选择
  List<WorkspaceTab> get displayedGridSessions =>
      broadcast ? broadcastSessions : gridSessions;

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
    _startPageRequested = false;
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
    _startPageRequested = false;
    gridEnabled = false;
    focusedGridId = null;
    notifyListeners();
  }

  /// 临时聚焦网格中的一个会话，不关闭其他连接。
  void focusGridSession(String id) {
    if (broadcast || !gridEnabled || !gridIds.contains(id)) return;
    _startPageRequested = false;
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
  /// 广播期间布局锁定为广播目标网格，只能在目标之间切换输入焦点。
  void selectTab(String id) {
    activate(id);
  }

  /// 调整标签顺序；即使活动标签未变或广播禁止激活，也必须通知界面刷新顺序。
  void reorderTab(int oldIndex, int newIndex) {
    if (oldIndex < 0 ||
        oldIndex >= tabs.length ||
        newIndex < 0 ||
        newIndex >= tabs.length ||
        oldIndex == newIndex) {
      return;
    }
    final tab = tabs.removeAt(oldIndex);
    tabs.insert(newIndex, tab);
    activate(tab.id);
    notifyListeners();
  }

  /// 广播模式：同步选中 SSH 的输入，期间以网格展示广播目标；原布局保留，停止后恢复。
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
    _startPageRequested = false;
    tabs.add(tab);
    // 广播期间布局锁定，新会话在后台打开，不打断广播网格
    if (!broadcast) {
      activeId = tab.id;
      // 单窗口期间也维护已保存的网格，避免关闭旧会话后新会话无法补入。
      // 尚未选择网格时仍由首次 showGrid 收集会话；广播期间不修改保存的布局。
      if (gridEnabled || gridIds.isNotEmpty) {
        if ((tab is TerminalSession || tab is RemoteDisplay) &&
            gridIds.length < maxGrid &&
            focusedGridId == null) {
          gridIds.add(tab.id);
        } else if (gridEnabled) {
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

  /// 所有激活入口统一维护可见布局，防止拖动标签或 SFTP 返回终端绕过限制。
  void activate(String id) {
    if (!tabs.any((t) => t.id == id)) return;
    if (broadcast && !broadcastIds.contains(id)) return;
    final previousFocus = focusedGridId;
    if (!broadcast &&
        gridEnabled &&
        (focusedGridId != null || !gridIds.contains(id))) {
      focusedGridId = id;
    }
    if (activeId == id &&
        previousFocus == focusedGridId &&
        !_startPageRequested) {
      return;
    }
    _startPageRequested = false;
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
      final visible = displayedGridSessions;
      activeId = showingGrid && visible.isNotEmpty
          ? visible.first.id
          : (tabs.isEmpty ? null : tabs.last.id);
    }
    if (!broadcast) _ensureActiveVisible();
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
    _startPageRequested = false;
    final tab = SftpTab(session);
    // 插入到对应终端标签之后，便于识别归属
    final at = tabs.indexOf(session);
    tabs.insert(at < 0 ? tabs.length : at + 1, tab);
    tab.addListener(notifyListeners);
    if (!broadcast) {
      activeId = tab.id;
      if (gridEnabled) focusedGridId = tab.id;
    }
    notifyListeners();
    return tab;
  }

  /// 开启或更新广播目标，只接受 SSH；不自动吸收新会话。
  /// 广播期间以网格展示目标，不修改用户保存的布局选择。
  bool startBroadcast({Iterable<String>? ids}) {
    final valid = terminals.map((t) => t.id).toSet();
    final selected = (ids ?? valid)
        .where(valid.contains)
        .toSet()
        .take(maxBroadcast)
        .toList();
    if (selected.isEmpty) return false;
    _startPageRequested = false;
    broadcastIds
      ..clear()
      ..addAll(selected);
    broadcast = true;
    if (!broadcastIds.contains(activeId)) activeId = broadcastIds.first;
    notifyListeners();
    return true;
  }

  /// 关闭广播，恢复广播前的布局
  void stopBroadcast() {
    broadcast = false;
    broadcastIds.clear();
    _ensureActiveVisible();
    notifyListeners();
  }

  /// 恢复布局时优先还原聚焦会话，否则确保输入焦点位于可见网格内。
  void _ensureActiveVisible() {
    if (gridEnabled && focusedGridId != null) {
      activeId = focusedGridId;
    } else if (showingGrid &&
        gridIds.isNotEmpty &&
        !gridIds.contains(activeId)) {
      activeId = gridIds.first;
    }
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
      if (broadcastIds.isEmpty) {
        broadcast = false;
        _ensureActiveVisible();
      } else if (activeId == id) {
        activeId = broadcastIds.first;
      }
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
