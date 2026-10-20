import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:remlark/data/database.dart';
import 'package:remlark/modules/keys/key_model.dart';
import 'package:remlark/modules/keys/key_repository.dart';
import 'package:remlark/utils/crypto_utils.dart';
import 'package:remlark/utils/secret_store.dart';

void main() {
  // 其他位置（如主机编辑器）增删密钥时，常驻的密钥页依赖仓库通知刷新
  test('保存与删除密钥会通知监听者', () async {
    SecretStore.initForTest(CryptoUtils.randomBytes(32));
    final db = AppDatabase(NativeDatabase.memory());
    final repo = KeyRepository(db);
    var notified = 0;
    repo.addListener(() => notified++);
    const key = KeyEntry(
      uuid: 'k1',
      name: 'test',
      keyType: 'ssh-ed25519',
      privateKey: 'pem',
      publicKey: 'ssh-ed25519 AAAA test',
      createdAt: 1,
    );
    await repo.save(key);
    expect(notified, 1);
    expect((await repo.list()).map((k) => k.uuid), ['k1']);
    await repo.delete('k1');
    expect(notified, 2);
    expect(await repo.list(), isEmpty);
    await db.close();
  });
}
