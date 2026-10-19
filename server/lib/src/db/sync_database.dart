import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';

part 'sync_database.g.dart';

/// 同步条目表：每个数据空间（由访问令牌决定）下按 uuid 存储加密载荷
@TableIndex(name: 'idx_items_space_uuid', columns: {#space, #uuid}, unique: true)
@TableIndex(name: 'idx_items_space_updated', columns: {#space, #updatedAt})
class SyncItems extends Table {
  IntColumn get id => integer().autoIncrement()();

  /// 数据空间 id（访问令牌的 SHA-256 前缀）
  TextColumn get space => text()();
  TextColumn get uuid => text()();

  /// 客户端提供的最后更新时间（毫秒）
  IntColumn get updatedAt => integer()();

  /// 删除标记：被删除的条目保留标记，供其他客户端停止同步
  BoolColumn get deleted => boolean().withDefault(const Constant(false))();

  /// 客户端加密后的载荷（服务端无法解密）
  TextColumn get payload => text().withDefault(const Constant(''))();
}

/// 同步服务数据库（drift ORM）
@DriftDatabase(tables: [SyncItems])
class SyncDatabase extends _$SyncDatabase {
  SyncDatabase(String path) : super(NativeDatabase.createInBackground(File(path)));

  SyncDatabase.memory() : super(NativeDatabase.memory());

  @override
  int get schemaVersion => 1;
}
