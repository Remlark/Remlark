import 'package:drift/drift.dart';

import 'sync_database.dart';

/// 写入结果
enum PutResult { stored, conflict }

/// 同步条目仓库：所有查询都带 space 条件，走 (space, uuid) / (space, updatedAt) 索引
class SyncRepository {
  SyncRepository(this._db);

  final SyncDatabase _db;

  /// 空间内全部条目的索引信息（不含载荷）
  Future<List<Map<String, Object>>> index(String space) async {
    final t = _db.syncItems;
    final rows =
        await (_db.selectOnly(t)
              ..addColumns([t.uuid, t.updatedAt, t.deleted])
              ..where(t.space.equals(space))
              ..orderBy([OrderingTerm.asc(t.updatedAt)]))
            .get();
    return [
      for (final r in rows) {'uuid': r.read(t.uuid)!, 'updatedAt': r.read(t.updatedAt)!, 'deleted': r.read(t.deleted)!},
    ];
  }

  /// 批量读取载荷
  Future<List<SyncItem>> fetch(String space, List<String> uuids) {
    return (_db.select(_db.syncItems)..where((t) => t.space.equals(space) & t.uuid.isIn(uuids))).get();
  }

  Future<SyncItem?> _get(String space, String uuid) {
    return (_db.select(_db.syncItems)..where((t) => t.space.equals(space) & t.uuid.equals(uuid))).getSingleOrNull();
  }

  /// 写入：服务器上的版本更新时返回冲突（由客户端拉取后再处理）
  Future<PutResult> put(String space, String uuid, int updatedAt, String payload) async {
    return _db.transaction(() async {
      final existing = await _get(space, uuid);
      if (existing == null) {
        await _db
            .into(_db.syncItems)
            .insert(SyncItemsCompanion.insert(space: space, uuid: uuid, updatedAt: updatedAt, payload: Value(payload)));
        return PutResult.stored;
      }
      if (existing.updatedAt > updatedAt && !existing.deleted) return PutResult.conflict;
      await (_db.update(_db.syncItems)..where((t) => t.id.equals(existing.id))).write(
        SyncItemsCompanion(updatedAt: Value(updatedAt), payload: Value(payload), deleted: const Value(false)),
      );
      return PutResult.stored;
    });
  }

  /// 删除：清空载荷并设置删除标记，返回条目是否存在
  Future<bool> delete(String space, String uuid) async {
    final n = await (_db.update(_db.syncItems)..where((t) => t.space.equals(space) & t.uuid.equals(uuid))).write(
      SyncItemsCompanion(
        deleted: const Value(true),
        payload: const Value(''),
        updatedAt: Value(DateTime.now().millisecondsSinceEpoch),
      ),
    );
    return n > 0;
  }
}
