import 'package:drift/drift.dart';

/// 数据库结构迁移工具：兼容旧版本号下已部分执行的 DDL，不改动业务数据。
class DatabaseMigrationUtils {
  DatabaseMigrationUtils._();

  /// 按实际结构补充缺失列，避免重复 ADD COLUMN 阻断启动。
  static Future<void> addColumnIfMissing(
    GeneratedDatabase db,
    Migrator migrator,
    TableInfo table,
    GeneratedColumn column,
  ) async {
    // 只读取指定表、指定列的系统元数据，不扫描业务表。
    final existing = await db
        .customSelect(
          'SELECT name FROM pragma_table_info(?) WHERE name = ?',
          variables: [Variable<String>(table.actualTableName), Variable<String>(column.$name)],
        )
        .get();
    if (existing.isEmpty) await migrator.addColumn(table, column);
  }

  /// 已存在的索引保持原样，缺失时使用 ORM 定义创建。
  static Future<void> createIndexIfMissing(GeneratedDatabase db, Migrator migrator, Index index) async {
    final existing = await db
        .customSelect(
          "SELECT name FROM sqlite_master WHERE type = 'index' AND name = ?",
          variables: [Variable<String>(index.entityName)],
        )
        .get();
    if (existing.isEmpty) await migrator.createIndex(index);
  }
}
