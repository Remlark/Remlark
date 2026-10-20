import 'package:drift/drift.dart';
import 'package:flutter/foundation.dart';

import '../../data/database.dart';
import '../../utils/secret_store.dart';
import 'key_model.dart';

/// 密钥仓库：私钥与口令加密存储。
/// 保存或删除后通知监听者，常驻页面（如密钥页）据此刷新，不必重新打开
class KeyRepository extends ChangeNotifier {
  KeyRepository(this._db);

  final AppDatabase _db;

  SecretStore get _secrets => SecretStore.instance;

  Future<KeyEntry> _toEntry(SshKey r) async => KeyEntry(
    uuid: r.uuid,
    name: r.name,
    keyType: r.keyType,
    privateKey: await _secrets.open(r.privateKeyEnc) ?? '',
    passphrase: await _secrets.open(r.passphraseEnc),
    publicKey: r.publicKey,
    createdAt: r.createdAt,
  );

  /// 列出全部密钥（按创建时间索引排序）
  Future<List<KeyEntry>> list() async {
    final rows =
        await (_db.select(_db.sshKeys)
              ..where((t) => t.createdAt.isBiggerOrEqualValue(0))
              ..orderBy([(t) => OrderingTerm.desc(t.createdAt)]))
            .get();
    return Future.wait(rows.map(_toEntry));
  }

  /// 按 uuid 获取
  Future<KeyEntry?> get(String uuid) async {
    final r = await (_db.select(_db.sshKeys)..where((t) => t.uuid.equals(uuid))).getSingleOrNull();
    return r == null ? null : _toEntry(r);
  }

  /// 保存（插入或更新）
  Future<void> save(KeyEntry k) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    final comp = SshKeysCompanion(
      uuid: Value(k.uuid),
      name: Value(k.name),
      keyType: Value(k.keyType),
      privateKeyEnc: Value(await _secrets.seal(k.privateKey) ?? ''),
      passphraseEnc: Value(await _secrets.seal(k.passphrase)),
      publicKey: Value(k.publicKey),
      createdAt: Value(k.createdAt),
      updatedAt: Value(now),
    );
    final exists = await (_db.select(_db.sshKeys)..where((t) => t.uuid.equals(k.uuid))).getSingleOrNull();
    if (exists == null) {
      await _db.into(_db.sshKeys).insert(comp);
    } else {
      await (_db.update(_db.sshKeys)..where((t) => t.uuid.equals(k.uuid))).write(comp);
    }
    notifyListeners();
  }

  /// 删除
  Future<void> delete(String uuid) async {
    await (_db.delete(_db.sshKeys)..where((t) => t.uuid.equals(uuid))).go();
    notifyListeners();
  }
}
