import 'package:drift/drift.dart';

import 'sync_database.dart';
import '../utils/serial_executor.dart';

/// 写入结果
enum PutResult { stored, conflict }

/// 同步条目仓库：所有查询都带 space 条件，走 (space, uuid) / (space, updatedAt) 索引
class SyncRepository {
  SyncRepository(this._db);

  final SyncDatabase _db;

  /// 服务端进程内所有客户端、空间和主机共享同一队列，比较和写入不会交错。
  static final SerialExecutor _operations = SerialExecutor();

  /// 空间内全部条目的索引信息（不含载荷）
  Future<List<Map<String, Object>>> index(String space) =>
      _operations.run(() async {
        final t = _db.syncItems;
        final rows =
            await (_db.selectOnly(t)
                  ..addColumns([t.uuid, t.updatedAt, t.deleted])
                  ..where(t.space.equals(space))
                  ..orderBy([OrderingTerm.asc(t.updatedAt)]))
                .get();
        return [
          for (final r in rows)
            {
              'uuid': r.read(t.uuid)!,
              'updatedAt': r.read(t.updatedAt)!,
              'deleted': r.read(t.deleted)!,
            },
        ];
      });

  /// 批量读取载荷
  Future<List<SyncItem>> fetch(String space, List<String> uuids) {
    return _operations.run(
      () => (_db.select(
        _db.syncItems,
      )..where((t) => t.space.equals(space) & t.uuid.isIn(uuids))).get(),
    );
  }

  Future<SyncItem?> _get(String space, String uuid) {
    return (_db.select(_db.syncItems)
          ..where((t) => t.space.equals(space) & t.uuid.equals(uuid)))
        .getSingleOrNull();
  }

  /// 写入：服务器上的版本更新时返回冲突（由客户端拉取后再处理）
  Future<PutResult> put(
    String space,
    String uuid,
    int updatedAt,
    String payload, {
    bool restoreDeleted = false,
  }) async {
    return _operations.run(
      () => _db.transaction(() async {
        final existing = await _get(space, uuid);
        if (existing == null) {
          await _db
              .into(_db.syncItems)
              .insert(
                SyncItemsCompanion.insert(
                  space: space,
                  uuid: uuid,
                  updatedAt: updatedAt,
                  payload: Value(payload),
                ),
              );
          return PutResult.stored;
        }
        // 普通同步不能复活另一端刚删除的主机，只有用户显式重新加入才恢复。
        if (existing.deleted && !restoreDeleted) return PutResult.conflict;
        // 已提交版本不可被另一份密文覆盖；相同请求重试保持幂等。
        if (!existing.deleted &&
            (existing.updatedAt > updatedAt ||
                (existing.updatedAt == updatedAt &&
                    existing.payload != payload))) {
          return PutResult.conflict;
        }
        await (_db.update(
          _db.syncItems,
        )..where((t) => t.id.equals(existing.id))).write(
          SyncItemsCompanion(
            updatedAt: Value(updatedAt),
            payload: Value(payload),
            deleted: const Value(false),
          ),
        );
        return PutResult.stored;
      }),
    );
  }

  /// 删除：清空载荷并设置删除标记，返回条目是否存在
  Future<bool> delete(String space, String uuid) => _operations.run(() async {
    final n =
        await (_db.update(
          _db.syncItems,
        )..where((t) => t.space.equals(space) & t.uuid.equals(uuid))).write(
          SyncItemsCompanion(
            deleted: const Value(true),
            payload: const Value(''),
            updatedAt: Value(DateTime.now().millisecondsSinceEpoch),
          ),
        );
    return n > 0;
  });
}
