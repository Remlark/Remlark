import 'package:drift/drift.dart';

import '../../data/database.dart';
import '../../utils/id_utils.dart';
import 'host_model.dart';

/// 分组仓库
class GroupRepository {
  GroupRepository(this._db);

  final AppDatabase _db;

  /// 按排序列出全部分组（sortOrder 索引排序；分组表本身即为过滤结果全集）
  Future<List<GroupEntry>> list() async {
    final rows =
        await (_db.select(_db.hostGroups)
              ..where((t) => t.sortOrder.isBiggerOrEqualValue(-1 << 31))
              ..orderBy([(t) => OrderingTerm.asc(t.sortOrder), (t) => OrderingTerm.asc(t.name)]))
            .get();
    return rows.map((r) => GroupEntry(uuid: r.uuid, name: r.name, sortOrder: r.sortOrder)).toList();
  }

  /// 新建或更新分组
  Future<GroupEntry> save(GroupEntry g) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    final existing = await (_db.select(_db.hostGroups)..where((t) => t.uuid.equals(g.uuid))).getSingleOrNull();
    if (existing == null) {
      await _db
          .into(_db.hostGroups)
          .insert(
            HostGroupsCompanion.insert(uuid: g.uuid, name: g.name, sortOrder: Value(g.sortOrder), updatedAt: now),
          );
    } else {
      await (_db.update(_db.hostGroups)..where((t) => t.uuid.equals(g.uuid))).write(
        HostGroupsCompanion(name: Value(g.name), sortOrder: Value(g.sortOrder), updatedAt: Value(now)),
      );
    }
    return g;
  }

  /// 按名称查找分组，不存在则创建（用于导入 / 同步时按名称映射分组）
  Future<GroupEntry> ensureByName(String name) async {
    final all = await list();
    for (final g in all) {
      if (g.name == name) return g;
    }
    return save(GroupEntry(uuid: IdUtils.newId(), name: name, sortOrder: all.length));
  }

  /// 删除分组
  Future<void> delete(String uuid) async {
    await (_db.delete(_db.hostGroups)..where((t) => t.uuid.equals(uuid))).go();
  }
}
