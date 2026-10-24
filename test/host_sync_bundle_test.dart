import 'dart:typed_data';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:remlark/data/database.dart';
import 'package:remlark/modules/hosts/host_model.dart';
import 'package:remlark/modules/hosts/host_repository.dart';
import 'package:remlark/modules/hosts/vnc_ssh_config.dart';
import 'package:remlark/modules/keys/key_model.dart';
import 'package:remlark/modules/keys/key_repository.dart';
import 'package:remlark/modules/sync/host_sync_bundle.dart';
import 'package:remlark/utils/secret_store.dart';

import 'helpers/sync_test_harness.dart';

/// 带附加 SSH 连接和本机信任指纹的测试主机。
HostEntry _host({int sshPort = 2222}) => HostEntry(
  uuid: 'host-1',
  protocol: HostProtocol.vnc,
  name: 'Ubuntu',
  address: 'ubuntu.example',
  port: 5900,
  password: 'vnc-password',
  savePassword: true,
  hostKeyFingerprint: 'local-vnc-fingerprint',
  extra: {
    'ssh': {'enabled': true, 'port': sshPort},
    'connections': {
      'ssh': {
        'protocol': 'ssh',
        'port': sshPort,
        'username': 'ubuntu',
        'authType': 'key',
        'keyUuid': 'ssh-key',
        'savePassword': false,
        'hostKeyFingerprint': 'local-ssh-fingerprint',
        'extra': <String, dynamic>{},
      },
    },
  },
  updatedAt: 123,
  createdAt: 1,
);

/// 为所有协议建立不同指纹，验证主协议切换时不会串用其他协议的信任记录。
HostEntry _withFingerprints(HostEntry host) => host.copyWith(
  hostKeyFingerprint: () => 'fp-${host.protocol.name}',
  extra: {
    ...host.extra,
    if (host.extra['connections'] case final Map profiles)
      'connections': {
        for (final item in profiles.entries)
          item.key: {
            ...(item.value as Map),
            'hostKeyFingerprint': 'fp-${item.key}',
          },
      },
  },
);

void main() {
  const key = KeyEntry(
    uuid: 'ssh-key',
    name: 'SSH key',
    keyType: 'ssh-ed25519',
    privateKey: 'private',
    publicKey: 'public',
    createdAt: 1,
  );

  test('单条快照包含所有协议和依赖，指纹不会进入载荷', () {
    final bundle = HostSyncBundle(
      host: _host(),
      groupName: 'servers',
      keys: [key],
    );
    expect(HostSyncBundle.referencedKeyUuids(bundle.host), {'ssh-key'});
    final json = bundle.toJson();
    expect(json['version'], HostSyncBundle.version);
    expect(json['group'], 'servers');
    expect((json['keys'] as List).length, 1);
    final portable = (json['host'] as Map)['extra'] as Map;
    final ssh = (portable['connections'] as Map)['ssh'] as Map;
    expect(ssh.containsKey('hostKeyFingerprint'), isFalse);
    final restored = HostSyncBundle.fromJson(json);
    restored.verifyServerRecord('host-1', 123);
    expect(
      () => restored.verifyServerRecord('other-host', 123),
      throwsFormatException,
    );
    expect(
      () => restored.verifyServerRecord('host-1', 124),
      throwsFormatException,
    );
    expect(restored.host.connectionProtocols, [
      HostProtocol.ssh,
      HostProtocol.vnc,
    ]);
    expect(restored.keys.single.uuid, 'ssh-key');
  });

  test('兼容旧单密钥载荷，拒绝不支持的新版本', () {
    final old = {'host': _host().toPortableJson(), 'key': key.toJson()};
    expect(HostSyncBundle.fromJson(old).keys.single.uuid, 'ssh-key');
    expect(
      () => HostSyncBundle.fromJson({...old, 'version': 999}),
      throwsFormatException,
    );
    expect(
      () => HostSyncBundle.fromJson({'version': 2}),
      throwsFormatException,
    );
  });

  test('拉取整个主机时仅对未变化的协议端点保留本机指纹', () {
    final local = _host();
    final same = HostSyncBundle(
      host: _host(),
      keys: const [],
    ).forDevice(local: local, groupUuid: 'group-1', updatedAt: 456);
    expect(same.hostKeyFingerprint, 'local-vnc-fingerprint');
    expect(
      same.forConnection(HostProtocol.ssh).hostKeyFingerprint,
      'local-ssh-fingerprint',
    );
    expect(same.groupUuid, 'group-1');
    expect(same.syncState, SyncState.synced);

    final changed = HostSyncBundle(
      host: _host(sshPort: 2223),
      keys: const [],
    ).forDevice(local: local, groupUuid: null, updatedAt: 457);
    expect(changed.forConnection(HostProtocol.ssh).hostKeyFingerprint, isNull);

    // 远端将 SSH 从主协议改为附加协议时，同一个 SSH 端点仍沿用本机指纹。
    final oldSshPrimary = local.copyWith(
      protocol: HostProtocol.ssh,
      port: 2222,
      extra: const {},
      hostKeyFingerprint: () => 'primary-ssh-fingerprint',
    );
    final switched = HostSyncBundle(
      host: _host(),
      keys: const [],
    ).forDevice(local: oldSshPrimary, groupUuid: null, updatedAt: 458);
    expect(
      switched.forConnection(HostProtocol.ssh).hostKeyFingerprint,
      'primary-ssh-fingerprint',
    );
  });

  test('主机快照事务失败时依赖密钥和主机一起回滚', () async {
    SecretStore.initForTest(Uint8List(32));
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    final hosts = HostRepository(db);
    final keys = KeyRepository(db);
    addTearDown(keys.dispose);
    await expectLater(
      hosts.transaction(() async {
        await keys.save(key);
        await hosts.save(_host());
        throw StateError('abort');
      }),
      throwsStateError,
    );
    expect(await hosts.getByUuid('host-1'), isNull);
    expect(await keys.get('ssh-key'), isNull);
  });

  test('本机保存生成严格递增版本，避免时钟回拨或同毫秒修改被误判未变', () async {
    SecretStore.initForTest(Uint8List(32));
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    final hosts = HostRepository(db);
    final futureVersion = DateTime.now().millisecondsSinceEpoch + 100000;
    await hosts.save(_host().copyWith(updatedAt: futureVersion), touch: false);
    final saved = await hosts.save(_host().copyWith(name: 'changed'));
    expect(saved.updatedAt, greaterThan(futureVersion));
    final savedAgain = await hosts.save(saved.copyWith(name: 'changed again'));
    expect(savedAgain.updatedAt, greaterThan(saved.updatedAt));
  });

  for (final badVersion in ['2', 0, -1, 1.5]) {
    test('非法载荷版本 $badVersion 拒绝按旧版本解析', () {
      expect(
        () => HostSyncBundle.fromJson({
          'version': badVersion,
          'host': _host().toPortableJson(),
        }),
        throwsFormatException,
      );
    });
  }

  test('旧单密钥和新密钥列表按 UUID 去重，忽略主机未引用的密钥', () {
    final json = HostSyncBundle(host: _host(), keys: [key]).toJson();
    json['key'] = key.toJson();
    json['keys'] = [
      key.toJson(),
      key.toJson(),
      {...key.toJson(), 'uuid': 'unrelated'},
    ];
    expect(HostSyncBundle.fromJson(json).keys.map((k) => k.uuid), ['ssh-key']);
  });

  test('旧版 VNC 内置 SSH 的密钥仍被收集', () {
    final legacy = _host().copyWith(
      extra: {
        'ssh': {'enabled': true, 'port': 22, 'auth': 'key', 'key': 'ssh-key'},
      },
    );
    expect(HostSyncBundle.referencedKeyUuids(legacy), {'ssh-key'});
    final decoded = HostSyncBundle.fromJson({
      'host': legacy.toPortableJson(),
      'key': key.toJson(),
    });
    expect(decoded.keys.single.uuid, 'ssh-key');
  });

  for (final invalid in ['primary-protocol', 'secondary-protocol', 'keys']) {
    test('损坏的 $invalid 字段不会静默降级或被忽略', () {
      final json = HostSyncBundle(host: _host(), keys: [key]).toJson();
      final host = json['host'] as Map;
      if (invalid == 'primary-protocol') host['protocol'] = 'telnet';
      if (invalid == 'secondary-protocol') {
        (host['extra'] as Map)['connections'] = {
          'telnet': {'port': 23},
        };
      }
      if (invalid == 'keys') json['keys'] = 'bad-list';
      expect(() => HostSyncBundle.fromJson(json), throwsFormatException);
    });
  }

  test('主机地址变化后清除所有旧指纹，最近连接时间只用本机值', () {
    final local = _host().copyWith(
      lastConnectedAt: () => 1234,
      osId: () => 'ubuntu',
      osName: () => 'Ubuntu 24.04',
    );
    final remote = _host().copyWith(
      address: 'new.example',
      lastConnectedAt: () => 9999,
    );
    final restored = HostSyncBundle(
      host: remote,
      keys: const [],
    ).forDevice(local: local, groupUuid: null, updatedAt: 200);
    expect(restored.hostKeyFingerprint, isNull);
    expect(restored.forConnection(HostProtocol.ssh).hostKeyFingerprint, isNull);
    expect(restored.lastConnectedAt, 1234);
    expect(restored.osId, 'ubuntu');
    final fresh = HostSyncBundle(
      host: remote,
      keys: const [],
    ).forDevice(local: null, groupUuid: null, updatedAt: 200);
    expect(fresh.lastConnectedAt, isNull);
  });

  test('附加协议未记住的密码即使残留在内存中也不进入载荷', () {
    final host = _host();
    final profile = host.connectionProfile(HostProtocol.ssh)!;
    final altered = host.copyWith(
      extra: {
        ...host.extra,
        'connections': {
          'ssh': {
            ...profile,
            'savePassword': false,
            'password': 'not-remembered',
          },
        },
      },
    );
    final json = HostSyncBundle(host: altered, keys: const []).toJson();
    final ssh =
        (((json['host'] as Map)['extra'] as Map)['connections'] as Map)['ssh']
            as Map;
    expect(ssh.containsKey('password'), isFalse);
  });

  for (var oldBits = 1; oldBits < 8; oldBits++) {
    for (var newBits = 1; newBits < 8; newBits++) {
      final before = {
        for (var i = 0; i < 3; i++)
          if ((oldBits & (1 << i)) != 0) HostProtocol.values[i],
      };
      final after = {
        for (var i = 0; i < 3; i++)
          if ((newBits & (1 << i)) != 0) HostProtocol.values[i],
      };
      test('协议组合 $oldBits → $newBits：整台替换入口，并按协议保留相同端点指纹', () {
        final local = _withFingerprints(protocolHost(before));
        final remote = protocolHost(after, version: 200);
        final restored = HostSyncBundle(
          host: remote,
          keys: const [],
        ).forDevice(local: local, groupUuid: null, updatedAt: 200);
        expect(restored.uuid, local.uuid);
        expect(restored.connectionProtocols.toSet(), after);
        for (final protocol in after) {
          final connection = restored.forConnection(protocol);
          expect(connection.password, '${protocol.name}-secret');
          expect(
            connection.hostKeyFingerprint,
            before.contains(protocol) ? 'fp-${protocol.name}' : null,
          );
        }
      });
    }
  }
}
