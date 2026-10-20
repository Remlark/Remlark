import 'package:flutter/foundation.dart';

import '../../utils/id_utils.dart';
import 'group_repository.dart';
import 'host_model.dart';
import 'host_repository.dart';
import 'vnc_ssh_config.dart';

/// 协议筛选
enum ProtocolFilter { all, ssh, rdp, vnc }

/// 主机列表控制器：分组、筛选、搜索与增删改
class HostsController extends ChangeNotifier {
  HostsController(this._hosts, this._groups);

  final HostRepository _hosts;
  final GroupRepository _groups;

  List<HostEntry> _all = [];
  List<GroupEntry> groups = [];

  /// “未分组”筛选的特殊值
  static const ungrouped = '__ungrouped__';

  /// 当前选中的分组（null 表示全部，[ungrouped] 表示未分组）
  String? selectedGroup;

  /// 列表视图（false 为卡片网格）
  bool listView = false;
  ProtocolFilter protocolFilter = ProtocolFilter.all;
  String search = '';
  bool loading = true;

  /// 全部主机
  List<HostEntry> get all => _all;

  /// 按筛选条件过滤后的主机
  List<HostEntry> get visible {
    final q = search.trim().toLowerCase();
    return _all.where((h) {
      if (selectedGroup == ungrouped) {
        if (h.groupUuid != null) return false;
      } else if (selectedGroup != null && h.groupUuid != selectedGroup) {
        return false;
      }
      if (protocolFilter != ProtocolFilter.all && !h.connectionProtocols.any((p) => p.name == protocolFilter.name)) {
        return false;
      }
      if (q.isEmpty) return true;
      return h.name.toLowerCase().contains(q) ||
          h.address.toLowerCase().contains(q) ||
          h.username.toLowerCase().contains(q) ||
          (h.osName?.toLowerCase().contains(q) ?? false);
    }).toList();
  }

  /// 最近连接的主机（最多 [n] 个）
  List<HostEntry> recent([int n = 6]) {
    final list = _all.where((h) => h.lastConnectedAt != null).toList()
      ..sort((a, b) => b.lastConnectedAt!.compareTo(a.lastConnectedAt!));
    return list.take(n).toList();
  }

  /// SSH 主机（用作跳板 / 文件传输主机候选）
  List<HostEntry> get sshHosts => _all
      .where((h) => h.connectionProtocols.contains(HostProtocol.ssh))
      .map((h) => h.forConnection(HostProtocol.ssh))
      .toList();

  /// 当前选中的真实分组 uuid（全部 / 未分组时为 null），用于新建主机、导入时的默认分组
  String? get selectedGroupUuid => selectedGroup == ungrouped ? null : selectedGroup;

  /// 某分组下的主机数量（null 为全部，[ungrouped] 为未分组）
  int countInGroup(String? groupUuid) => switch (groupUuid) {
    null => _all.length,
    ungrouped => _all.where((h) => h.groupUuid == null).length,
    _ => _all.where((h) => h.groupUuid == groupUuid).length,
  };

  /// 从数据库重新加载
  Future<void> load() async {
    _all = await _hosts.listByProtocols(HostProtocol.values.toSet());
    groups = await _groups.list();
    if (selectedGroup != null && selectedGroup != ungrouped && !groups.any((g) => g.uuid == selectedGroup)) {
      selectedGroup = null;
    }
    loading = false;
    notifyListeners();
  }

  void setGroup(String? g) {
    selectedGroup = g;
    notifyListeners();
  }

  /// 切换卡片 / 列表视图
  void setListView(bool v) {
    listView = v;
    notifyListeners();
  }

  void setProtocolFilter(ProtocolFilter f) {
    protocolFilter = f;
    notifyListeners();
  }

  void setSearch(String s) {
    search = s;
    notifyListeners();
  }

  /// 按 uuid 查找
  HostEntry? byUuid(String uuid) {
    for (final h in _all) {
      if (h.uuid == uuid) return h;
    }
    return null;
  }

  /// 保存主机
  Future<HostEntry> saveHost(HostEntry h) async {
    final saved = await _hosts.save(h);
    await load();
    return saved;
  }

  /// 复制主机
  Future<void> duplicate(HostEntry h) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    await _hosts.save(
      h.copyWith(
        uuid: IdUtils.newId(),
        name: '${h.name} (copy)',
        syncEnabled: false,
        syncedAt: () => null,
        createdAt: now,
        lastConnectedAt: () => null,
      ),
    );
    await load();
  }

  /// 删除主机，并从其他主机的跳板链中移除
  Future<void> deleteHost(String uuid) async {
    await _hosts.delete(uuid);
    for (final h in _all.where((h) => h.jumpChain.contains(uuid))) {
      await _hosts.save(h.copyWith(jumpChain: h.jumpChain.where((j) => j != uuid).toList()));
    }
    await load();
  }

  /// 新建或重命名分组
  Future<void> saveGroup(GroupEntry g) async {
    await _groups.save(g);
    await load();
  }

  /// 删除分组（组内主机移到未分组）
  Future<void> deleteGroup(String uuid) async {
    await _hosts.clearGroup(uuid);
    await _groups.delete(uuid);
    await load();
  }
}
