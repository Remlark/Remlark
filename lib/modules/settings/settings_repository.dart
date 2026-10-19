import 'dart:convert';

import '../../data/database.dart';

/// 设置仓库：键值对存储（主键查询）
class SettingsRepository {
  SettingsRepository(this._db);

  final AppDatabase _db;

  /// 读取字符串设置
  Future<String?> get(String key) async {
    final row = await (_db.select(_db.appSettings)..where((t) => t.key.equals(key))).getSingleOrNull();
    return row?.value;
  }

  /// 写入字符串设置
  Future<void> set(String key, String value) async {
    await _db.into(_db.appSettings).insertOnConflictUpdate(AppSettingsCompanion.insert(key: key, value: value));
  }

  /// 删除设置
  Future<void> remove(String key) async {
    await (_db.delete(_db.appSettings)..where((t) => t.key.equals(key))).go();
  }

  /// 读取 JSON 设置
  Future<Map<String, dynamic>> getJson(String key) async {
    final v = await get(key);
    if (v == null || v.isEmpty) return {};
    try {
      return Map<String, dynamic>.from(jsonDecode(v) as Map);
    } catch (_) {
      return {};
    }
  }

  /// 写入 JSON 设置
  Future<void> setJson(String key, Map<String, dynamic> value) => set(key, jsonEncode(value));

  /// 读取整数设置
  Future<int?> getInt(String key) async => int.tryParse(await get(key) ?? '');

  /// 批量读取多个 key（主键 IN 查询）
  Future<Map<String, String>> getMany(List<String> keys) async {
    final rows = await (_db.select(_db.appSettings)..where((t) => t.key.isIn(keys))).get();
    return {for (final r in rows) r.key: r.value};
  }

  /// 数据库实例（用于事务）
  AppDatabase get db => _db;
}
