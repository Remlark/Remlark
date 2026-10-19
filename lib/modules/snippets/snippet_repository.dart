import 'package:drift/drift.dart';

import '../../data/database.dart';
import '../../utils/id_utils.dart';
import '../../utils/platform_utils.dart';
import 'snippet_model.dart';

/// 快捷指令仓库
class SnippetRepository {
  SnippetRepository(this._db);

  final AppDatabase _db;

  SnippetEntry _toEntry(Snippet r) => SnippetEntry(
    uuid: r.uuid,
    name: r.name,
    content: r.content,
    kind: SnippetKind.parse(r.kind),
    autoEnter: r.autoEnter,
    sortOrder: r.sortOrder,
  );

  /// 按排序列出（sortOrder 索引）
  Future<List<SnippetEntry>> list() async {
    final rows =
        await (_db.select(_db.snippets)
              ..where((t) => t.sortOrder.isBiggerOrEqualValue(-1 << 31))
              ..orderBy([(t) => OrderingTerm.asc(t.sortOrder), (t) => OrderingTerm.asc(t.id)]))
            .get();
    return rows.map(_toEntry).toList();
  }

  /// 保存（插入或更新）
  Future<void> save(SnippetEntry s) async {
    final comp = SnippetsCompanion(
      uuid: Value(s.uuid),
      name: Value(s.name),
      content: Value(s.content),
      kind: Value(s.kind.value),
      autoEnter: Value(s.autoEnter),
      sortOrder: Value(s.sortOrder),
      updatedAt: Value(DateTime.now().millisecondsSinceEpoch),
    );
    final exists = await (_db.select(_db.snippets)..where((t) => t.uuid.equals(s.uuid))).getSingleOrNull();
    if (exists == null) {
      await _db.into(_db.snippets).insert(comp);
    } else {
      await (_db.update(_db.snippets)..where((t) => t.uuid.equals(s.uuid))).write(comp);
    }
  }

  /// 删除
  Future<void> delete(String uuid) async {
    await (_db.delete(_db.snippets)..where((t) => t.uuid.equals(uuid))).go();
  }

  /// 首次启动时写入内置快捷指令（特殊动作仅在 macOS / Linux 提供）
  Future<void> seedDefaults({required String installKeyName}) async {
    final existing = await list();
    if (existing.isNotEmpty) return;
    if (PlatformUtils.isUnixDesktop) {
      await save(
        SnippetEntry(uuid: IdUtils.newId(), name: installKeyName, kind: SnippetKind.installSystemKey, sortOrder: 0),
      );
    }
    await save(SnippetEntry(uuid: IdUtils.newId(), name: 'df -h', content: 'df -h', sortOrder: 1));
    await save(SnippetEntry(uuid: IdUtils.newId(), name: 'top', content: 'top', sortOrder: 2));
  }
}
