import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:remlark/data/database.dart';
import 'package:remlark/modules/hosts/group_repository.dart';
import 'package:remlark/modules/hosts/host_model.dart';
import 'package:remlark/modules/hosts/host_repository.dart';
import 'package:remlark/modules/keys/key_repository.dart';
import 'package:remlark/modules/settings/settings_repository.dart';
import 'package:remlark/modules/sync/sync_config.dart';
import 'package:remlark/modules/sync/sync_service.dart';
import 'package:remlark/utils/crypto_utils.dart';
import 'package:remlark/utils/secret_store.dart';

/// 模拟一个客户端（独立内存数据库）
class _Client {
  _Client(String url) {
    final db = AppDatabase(NativeDatabase.memory());
    hosts = HostRepository(db);
    final groups = GroupRepository(db);
    sync = SyncService(SettingsRepository(db), hosts, groups, KeyRepository(db));
    sync.config = SyncConfig(serverUrl: url, token: 'tok', passphrase: 'pass');
  }

  late final HostRepository hosts;
  late final SyncService sync;
}

HostEntry _host(String uuid, String name) => HostEntry(
  uuid: uuid,
  protocol: HostProtocol.ssh,
  name: name,
  address: '10.0.0.1',
  port: 22,
  username: 'root',
  password: 'pw',
  savePassword: true,
  syncEnabled: true,
  updatedAt: 0,
  createdAt: 0,
);

void main() {
  late Process server;
  late String url;

  setUpAll(() async {
    SecretStore.initForTest(CryptoUtils.randomBytes(32));
    final port = 18000 + DateTime.now().millisecond;
    final dbFile = '${Directory.systemTemp.createTempSync('rmk').path}/s.sqlite';
    server = await Process.start('dart', [
      'run',
      'bin/server.dart',
      '--port',
      '$port',
      '--token',
      'tok',
      '--db',
      dbFile,
    ], workingDirectory: 'server');
    final ready = Completer<void>();
    server.stdout.transform(utf8.decoder).listen((l) {
      if (l.contains('listening') && !ready.isCompleted) ready.complete();
    });
    server.stderr.transform(utf8.decoder).listen((_) {});
    await ready.future.timeout(const Duration(seconds: 60));
    url = 'http://127.0.0.1:$port';
  });

  tearDownAll(() => server.kill());

  test('两个客户端通过服务器同步：上传、拉取、更新、删除标记、口令错误', () async {
    final a = _Client(url);
    final b = _Client(url);

    await a.hosts.save(_host('h1', 'web'));
    var r = await a.sync.syncNow();
    expect(r.pushed, 1);
    expect((await a.hosts.getByUuid('h1'))!.syncState, SyncState.synced);

    // B 拉取到 A 的主机，包括密码
    r = await b.sync.syncNow();
    expect(r.pulled, 1);
    final bh = (await b.hosts.getByUuid('h1'))!;
    expect(bh.name, 'web');
    expect(bh.password, 'pw');
    expect(bh.syncState, SyncState.synced);

    // B 修改后变为待同步，同步后 A 获得更新
    await Future.delayed(const Duration(milliseconds: 5));
    await b.hosts.save(bh.copyWith(name: 'web-renamed'));
    expect((await b.hosts.getByUuid('h1'))!.syncState, SyncState.pending);
    await b.sync.syncNow();
    r = await a.sync.syncNow();
    expect(r.pulled, 1);
    expect((await a.hosts.getByUuid('h1'))!.name, 'web-renamed');

    // A 从服务器删除，B 同步后变为仅本地
    await a.sync.removeFromServer('h1');
    await b.sync.syncNow();
    expect((await b.hosts.getByUuid('h1'))!.syncState, SyncState.local);

    // 口令不一致时报错
    final c = _Client(url);
    c.sync.config = SyncConfig(serverUrl: url, token: 'tok', passphrase: 'other');
    await a.hosts.save(_host('h2', 'db'));
    await a.sync.syncNow();
    await expectLater(c.sync.syncNow(), throwsA(anything));
    expect(c.sync.lastError, 'sync.error.passphrase');
  });
}
