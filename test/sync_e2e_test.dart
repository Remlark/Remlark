import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:remlark/data/database.dart';
import 'package:remlark/modules/hosts/group_repository.dart';
import 'package:remlark/modules/hosts/host_model.dart';
import 'package:remlark/modules/hosts/host_repository.dart';
import 'package:remlark/modules/hosts/ui/host_connection_forms.dart';
import 'package:remlark/modules/hosts/vnc_ssh_config.dart';
import 'package:remlark/modules/keys/key_model.dart';
import 'package:remlark/modules/keys/key_repository.dart';
import 'package:remlark/modules/settings/settings_repository.dart';
import 'package:remlark/modules/sync/sync_config.dart';
import 'package:remlark/modules/sync/sync_service.dart';
import 'package:remlark/utils/crypto_utils.dart';
import 'package:remlark/utils/secret_store.dart';

import 'helpers/platform_tools.dart';

/// 模拟一个客户端（独立内存数据库）
class _Client {
  _Client(String url) {
    final db = AppDatabase(NativeDatabase.memory());
    hosts = HostRepository(db);
    keys = KeyRepository(db);
    final groups = GroupRepository(db);
    sync = SyncService(SettingsRepository(db), hosts, groups, keys);
    sync.config = SyncConfig(serverUrl: url, token: 'tok', passphrase: 'pass');
    addTearDown(() async {
      sync.dispose();
      keys.dispose();
      await db.close();
    });
  }

  late final HostRepository hosts;
  late final KeyRepository keys;
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
  Process? server;
  late Directory serverDirectory;
  late String url;

  setUpAll(() async {
    SecretStore.initForTest(CryptoUtils.randomBytes(32));
    serverDirectory = Directory.systemTemp.createTempSync('rmk-sync-test');
    final dbFile = '${serverDirectory.path}/s.sqlite';
    final process = await Process.start(dartExecutable(), [
      'run',
      'bin/server.dart',
      '--port',
      '0',
      '--token',
      'tok',
      '--db',
      dbFile,
    ], workingDirectory: 'server');
    server = process;
    final ready = Completer<void>();
    process.stdout
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen((line) {
          final match = RegExp(r'listening on (http://\S+)').firstMatch(line);
          if (match != null && !ready.isCompleted) {
            url = 'http://127.0.0.1:${Uri.parse(match.group(1)!).port}';
            ready.complete();
          }
        });
    process.stderr.transform(utf8.decoder).listen((_) {});
    await ready.future.timeout(const Duration(seconds: 60));
  });

  tearDownAll(() async {
    server?.kill();
    await server?.exitCode;
    await serverDirectory.delete(recursive: true);
  });

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
    c.sync.config = SyncConfig(
      serverUrl: url,
      token: 'tok',
      passphrase: 'other',
    );
    await a.hosts.save(_host('h2', 'db'));
    await a.sync.syncNow();
    await expectLater(c.sync.syncNow(), throwsA(anything));
    expect(c.sync.lastError, 'sync.error.passphrase');
  });

  test('同一主机的 SSH、VNC、RDP 配置和附加 SSH 密钥跨客户端同步', () async {
    final a = _Client(url);
    final b = _Client(url);
    const key = KeyEntry(
      uuid: 'multi-ssh-key',
      name: 'multi key',
      keyType: 'ssh-ed25519',
      privateKey: 'test-private-key',
      publicKey: 'ssh-ed25519 AAAA multi',
      createdAt: 1,
    );
    await a.keys.save(key);
    final forms = HostConnectionForms(null, HostProtocol.vnc, null);
    addTearDown(forms.dispose);
    forms.current.name.text = 'PVE-Ubuntu';
    forms.current.address.text = '10.0.0.8';
    forms.current.username.text = 'vnc-user';
    forms.current.password.text = 'vnc-password';
    forms.osOverride = 'ubuntu';
    forms.enabled.addAll({HostProtocol.ssh, HostProtocol.rdp});
    forms.select(HostProtocol.ssh);
    forms.current.port.text = '2222';
    forms.current.username.text = 'ssh-user';
    forms.current.authType = AuthType.key;
    forms.current.keyUuid = key.uuid;
    forms.current.proxyType = ProxyType.socks5;
    forms.current.proxyHost.text = 'proxy.example';
    forms.current.proxyPort.text = '1080';
    forms.current.proxyPass.text = 'proxy-password';
    forms.select(HostProtocol.rdp);
    forms.current.port.text = '3390';
    forms.current.username.text = 'rdp-user';
    forms.current.password.text = 'rdp-password';
    forms.current.syncEnabled = true;
    final source = await a.hosts.save(forms.build());
    expect(source.connectionProtocols, HostProtocol.values);
    await a.hosts.updateFingerprint(
      source.uuid,
      'local-ssh-fingerprint',
      protocol: HostProtocol.ssh,
    );

    expect((await a.sync.syncNow()).pushed, 1);
    expect((await b.sync.syncNow()).pulled, greaterThanOrEqualTo(1));
    final restored = (await b.hosts.getByUuid(source.uuid))!;
    expect(restored.connectionProtocols, HostProtocol.values);
    expect(restored.syncState, SyncState.synced);
    expect(restored.extra['osOverride'], 'ubuntu');
    expect(restored.forConnection(HostProtocol.vnc).password, 'vnc-password');
    expect(restored.forConnection(HostProtocol.ssh).port, 2222);
    expect(restored.forConnection(HostProtocol.ssh).keyUuid, key.uuid);
    expect(restored.forConnection(HostProtocol.ssh).proxy.port, 1080);
    expect(
      restored.forConnection(HostProtocol.ssh).proxy.password,
      'proxy-password',
    );
    expect(restored.forConnection(HostProtocol.ssh).hostKeyFingerprint, isNull);
    expect(restored.forConnection(HostProtocol.rdp).port, 3390);
    expect(restored.forConnection(HostProtocol.rdp).password, 'rdp-password');
    expect((await b.keys.get(key.uuid))?.privateKey, key.privateKey);

    // B 改动附加 RDP 配置后，A 能按主机 uuid 拉回完整的新版本。
    final modified = restored.copyWith(
      extra: {
        ...restored.extra,
        'connections': {
          ...(restored.extra['connections'] as Map),
          'rdp': {
            ...restored.connectionProfile(HostProtocol.rdp)!,
            'port': 3391,
          },
        },
      },
    );
    await Future.delayed(const Duration(milliseconds: 5));
    await b.hosts.save(modified);
    await b.sync.syncNow();
    expect((await a.sync.syncNow()).pulled, 1);
    expect(
      (await a.hosts.getByUuid(source.uuid))!
          .forConnection(HostProtocol.rdp)
          .port,
      3391,
    );
    expect(
      (await a.hosts.getByUuid(source.uuid))!
          .forConnection(HostProtocol.ssh)
          .hostKeyFingerprint,
      'local-ssh-fingerprint',
    );
  });

  test('两个客户端同时同步各自主机，服务端串行处理后两端均能补齐配置', () async {
    final a = _Client(url);
    final b = _Client(url);
    await a.hosts.save(_host('parallel-a', 'client-a'));
    await b.hosts.save(_host('parallel-b', 'client-b'));
    await Future.wait([a.sync.syncNow(), b.sync.syncNow()]);
    await Future.wait([a.sync.syncNow(), b.sync.syncNow()]);
    expect((await a.hosts.getByUuid('parallel-b'))!.name, 'client-b');
    expect((await b.hosts.getByUuid('parallel-a'))!.name, 'client-a');
  });
}
