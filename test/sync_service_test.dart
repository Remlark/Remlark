import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:remlark/modules/hosts/host_model.dart';
import 'package:remlark/modules/hosts/host_repository.dart';
import 'package:remlark/modules/hosts/vnc_ssh_config.dart';
import 'package:remlark/modules/keys/key_model.dart';
import 'package:remlark/modules/settings/settings_repository.dart';
import 'package:remlark/modules/sync/host_sync_bundle.dart';
import 'package:remlark/modules/sync/sync_api.dart';
import 'package:remlark/modules/sync/sync_config.dart';
import 'package:remlark/modules/sync/sync_service.dart';
import 'package:remlark/utils/secret_store.dart';

import 'helpers/sync_test_harness.dart';

/// 在下载写入主机时制造故障，验证真实同步事务会回滚依赖。
class _FailingHostRepository extends HostRepository {
  _FailingHostRepository(super.db);

  bool fail = false;

  /// 按测试阶段注入数据库故障。
  @override
  Future<HostEntry> save(HostEntry host, {bool touch = true}) {
    if (fail) throw StateError('host save failed');
    return super.save(host, touch: touch);
  }
}

void main() {
  late MemorySyncApi api;
  late SyncTestClient client;

  setUp(() {
    SecretStore.initForTest(Uint8List(32));
    api = MemorySyncApi();
    client = SyncTestClient(api);
  });

  group('同步方向与状态', () {
    test('未配置时拒绝同步且不请求服务器', () async {
      client.sync.config = const SyncConfig();
      await expectLater(client.sync.syncNow(), throwsStateError);
      expect(api.indexCalls, 0);
      expect(client.sync.syncing, isFalse);
    });

    test('两端均为空时成功，无上传下载并记录完成时间', () async {
      final report = await client.sync.syncNow();
      expect([report.pushed, report.pulled, report.unchanged], [0, 0, 0]);
      expect(client.sync.config.lastSyncAt, isNotNull);
      expect(client.sync.lastError, isNull);
    });

    test('仅本地且未开启同步的主机不会上传', () async {
      await client.save(syncHost(enabled: false));
      await client.sync.syncNow();
      expect(api.putCalls, 0);
      expect((await client.hosts.getByUuid('h1'))!.syncState, SyncState.local);
    });

    test('本地新增主机上传一条密文，成功后已同步', () async {
      await client.save(syncHost());
      final report = await client.sync.syncNow();
      expect(report.pushed, 1);
      expect(api.records.keys, ['h1']);
      expect(api.records['h1']!.payload, startsWith('v2:gzip:'));
      expect(api.records['h1']!.payload, isNot(contains('host-secret')));
      expect(
        (await api.decoded('h1'))['host'],
        containsPair('password', 'host-secret'),
      );
      expect((await client.hosts.getByUuid('h1'))!.syncState, SyncState.synced);
    });

    test('远端新增主机完整拉取并加入同步', () async {
      await api.seed(syncHost());
      final report = await client.sync.syncNow();
      expect(report.pulled, 1);
      final local = (await client.hosts.getByUuid('h1'))!;
      expect(local.password, 'host-secret');
      expect(local.syncState, SyncState.synced);
    });

    for (final (localVersion, remoteVersion, direction) in [
      (200, 100, '本地较新'),
      (100, 200, '远端较新'),
      (100, 100, '版本相同'),
    ]) {
      test('$direction：正确选择方向并修复同步状态', () async {
        await client.save(syncHost(version: localVersion, name: 'local'));
        await api.seed(syncHost(version: remoteVersion, name: 'remote'));
        final report = await client.sync.syncNow();
        final local = (await client.hosts.getByUuid('h1'))!;
        expect(local.syncState, SyncState.synced);
        expect(local.name, localVersion > remoteVersion ? 'local' : 'remote');
        expect([
          report.pushed,
          report.pulled,
          report.unchanged,
        ], localVersion > remoteVersion ? [1, 0, 0] : [0, 1, 0]);
      });
    }

    for (final newerLocal in [true, false]) {
      test(
        '同 UUID 的仅本地主机与远端合并，${newerLocal ? '上传本地新版本' : '拉取远端新版本'}',
        () async {
          await client.save(
            syncHost(
              version: newerLocal ? 200 : 50,
              enabled: false,
              name: 'local',
            ),
          );
          await api.seed(syncHost(name: 'remote'));
          await client.sync.syncNow();
          final local = (await client.hosts.getByUuid('h1'))!;
          expect(local.name, newerLocal ? 'local' : 'remote');
          expect(local.syncState, SyncState.synced);
        },
      );
    }

    test('重复同步无改动时不重新上传或下载', () async {
      await client.save(syncHost());
      await client.sync.syncNow();
      final report = await client.sync.syncNow();
      expect(report.unchanged, 1);
      expect(api.putCalls, 1);
      expect(api.fetchCalls, 0);
    });

    test('连接多次、系统探测及指纹变化不会产生新的同步上传', () async {
      await client.save(protocolHost(HostProtocol.values.toSet()));
      await client.sync.syncNow();
      await client.hosts.touchConnected('h1');
      await client.hosts.touchConnected('h1');
      await client.hosts.updateOs('h1', 'ubuntu', 'Ubuntu 24.04');
      for (final protocol in HostProtocol.values) {
        await client.hosts.updateFingerprint(
          'h1',
          'fp-${protocol.name}',
          protocol: protocol,
        );
      }
      final report = await client.sync.syncNow();
      expect(report.unchanged, 1);
      expect(api.putCalls, 1);
      expect(api.fetchCalls, 0);
      expect((await client.hosts.getByUuid('h1'))!.updatedAt, 100);
    });
  });

  group('多协议、凭据与分组', () {
    test('两端修改不同协议仍按主机整份版本取舍，不混合不同版本的连接配置', () async {
      final local = protocolHost(HostProtocol.values.toSet(), version: 200);
      await client.save(local.copyWith(username: 'local-ssh-edit'));
      final remote = protocolHost(HostProtocol.values.toSet(), version: 300);
      await api.seed(
        remote.copyWith(
          extra: {
            ...remote.extra,
            'connections': {
              ...(remote.extra['connections'] as Map),
              'rdp': {
                ...remote.connectionProfile(HostProtocol.rdp)!,
                'username': 'remote-rdp-edit',
              },
            },
          },
        ),
      );
      await client.sync.syncNow();
      final restored = (await client.hosts.getByUuid('h1'))!;
      expect(restored.username, 'ssh-user');
      expect(
        restored.forConnection(HostProtocol.rdp).username,
        'remote-rdp-edit',
      );
      expect(restored.updatedAt, 300);
      expect(restored.connectionProtocols.length, 3);
    });

    for (var bits = 1; bits < 8; bits++) {
      final protocols = {
        for (var i = 0; i < 3; i++)
          if ((bits & (1 << i)) != 0) HostProtocol.values[i],
      };
      test(
        '${protocols.map((p) => p.name).join('+')} 组合整台同步且各协议参数独立',
        () async {
          final source = protocolHost(protocols);
          await api.seed(source);
          await client.sync.syncNow();
          final local = (await client.hosts.getByUuid('h1'))!;
          expect(local.connectionProtocols.toSet(), protocols);
          for (final protocol in protocols) {
            final connection = local.forConnection(protocol);
            expect(connection.username, '${protocol.name}-user');
            expect(connection.password, '${protocol.name}-secret');
            expect(connection.port, protocol.defaultPort + 1);
            expect(connection.proxy.password, 'proxy-secret');
            expect(connection.extra['osOverride'], 'ubuntu');
            if (protocol == HostProtocol.rdp) {
              expect(connection.extra['domain'], 'office');
            }
          }
        },
      );
    }

    test('新增和移除连接方式均替换整台主机，不留下旧入口', () async {
      await api.seed(protocolHost({HostProtocol.ssh}));
      await client.sync.syncNow();
      await api.seed(protocolHost(HostProtocol.values.toSet(), version: 200));
      await client.sync.syncNow();
      expect(
        (await client.hosts.getByUuid('h1'))!.connectionProtocols.toSet(),
        HostProtocol.values.toSet(),
      );
      await api.seed(protocolHost({HostProtocol.rdp}, version: 300));
      await client.sync.syncNow();
      expect((await client.hosts.getByUuid('h1'))!.connectionProtocols, [
        HostProtocol.rdp,
      ]);
      expect(api.records.length, 1);
    });

    test('未记住的密码不会随任何协议同步', () async {
      await client.save(
        protocolHost(HostProtocol.values.toSet(), remember: false),
      );
      await client.sync.syncNow();
      final restored = HostSyncBundle.fromJson(await api.decoded('h1')).host;
      for (final protocol in restored.connectionProtocols) {
        expect(restored.forConnection(protocol).password, isNull);
        expect(restored.forConnection(protocol).savePassword, isFalse);
      }
    });

    test('同名分组使用本机已有 UUID，取消分组能清除本机关联', () async {
      await client.groups.save(
        const GroupEntry(uuid: 'local-group', name: 'Production'),
      );
      await api.seed(syncHost(), groupName: 'Production');
      await client.sync.syncNow();
      expect((await client.hosts.getByUuid('h1'))!.groupUuid, 'local-group');
      expect((await client.groups.list()).length, 1);
      await api.seed(syncHost(version: 200));
      await client.sync.syncNow();
      expect((await client.hosts.getByUuid('h1'))!.groupUuid, isNull);
    });

    test('远端取消记住密码后，下载清除本机所有协议的旧密码', () async {
      await api.seed(protocolHost(HostProtocol.values.toSet()));
      await client.sync.syncNow();
      await api.seed(
        protocolHost(
          HostProtocol.values.toSet(),
          version: 200,
          remember: false,
        ),
      );
      await client.sync.syncNow();
      final host = (await client.hosts.getByUuid('h1'))!;
      for (final protocol in host.connectionProtocols) {
        expect(host.forConnection(protocol).password, isNull);
        expect(host.forConnection(protocol).savePassword, isFalse);
      }
    });
  });

  group('删除、启用与失败恢复', () {
    test('尚未配置服务器时开启同步，只标记待同步', () async {
      final host = syncHost(enabled: false);
      await client.save(host);
      client.sync.config = const SyncConfig();
      await client.sync.enable(host);
      expect(
        (await client.hosts.getByUuid('h1'))!.syncState,
        SyncState.pending,
      );
      expect(api.putCalls, 0);
    });

    test('远端删除优先于未上传的本地修改，本地主机保留', () async {
      await client.save(syncHost(version: 5000));
      api.tombstone('h1');
      final report = await client.sync.syncNow();
      expect(report.detached, 1);
      expect(api.putCalls, 0);
      expect((await client.hosts.getByUuid('h1'))!.syncState, SyncState.local);
    });

    test('远端删除记录而本机无主机时，不创建占位主机', () async {
      api.tombstone('h1');
      await client.sync.syncNow();
      expect(await client.hosts.getByUuid('h1'), isNull);
    });

    test('从服务器移除多协议主机，本机全部配置保留并停止同步', () async {
      await client.save(protocolHost(HostProtocol.values.toSet()));
      await client.sync.syncNow();
      await client.sync.removeFromServer('h1');
      final local = (await client.hosts.getByUuid('h1'))!;
      expect(local.syncState, SyncState.local);
      expect(local.connectionProtocols.length, 3);
      expect(api.records['h1']!.deleted, isTrue);
    });

    test('删除请求失败时本机仍保持原同步状态，可重试', () async {
      await client.save(syncHost());
      await client.sync.syncNow();
      api.deleteError = const SyncApiException(503, 'offline');
      await expectLater(
        client.sync.removeFromServer('h1'),
        throwsA(isA<SyncApiException>()),
      );
      expect((await client.hosts.getByUuid('h1'))!.syncState, SyncState.synced);
      api.deleteError = null;
      await client.sync.removeFromServer('h1');
      expect((await client.hosts.getByUuid('h1'))!.syncState, SyncState.local);
    });

    test('显式重新加入同步可以恢复已删除的服务器记录', () async {
      final host = syncHost(enabled: false);
      await client.save(host);
      api.tombstone('h1');
      await client.sync.enable(host);
      expect(api.records['h1']!.deleted, isFalse);
      expect((await client.hosts.getByUuid('h1'))!.syncState, SyncState.synced);
    });

    test('启用同步但服务器离线时保留待同步，恢复后可上传', () async {
      final host = syncHost(enabled: false);
      await client.save(host);
      api.putError = const SyncApiException(503, 'offline');
      await client.sync.enable(host);
      expect(
        (await client.hosts.getByUuid('h1'))!.syncState,
        SyncState.pending,
      );
      api.putError = null;
      expect((await client.sync.syncNow()).pushed, 1);
    });

    for (final stage in ['index', 'put', 'fetch']) {
      test('$stage 网络失败后状态复原，重试可以成功', () async {
        const error = SyncApiException(503, 'offline');
        if (stage == 'put') await client.save(syncHost());
        if (stage == 'fetch') await api.seed(syncHost());
        if (stage == 'index') api.indexError = error;
        if (stage == 'put') api.putError = error;
        if (stage == 'fetch') api.fetchError = error;
        await expectLater(
          client.sync.syncNow(),
          throwsA(isA<SyncApiException>()),
        );
        expect(client.sync.syncing, isFalse);
        expect(client.sync.lastError, contains('503'));
        expect(client.sync.config.lastSyncAt, isNull);
        api.indexError = api.putError = api.fetchError = null;
        await client.sync.syncNow();
        expect(client.sync.lastError, isNull);
      });
    }

    test('密码错误不会改写本地配置，修正口令后可重试', () async {
      await api.seed(syncHost(version: 200));
      await client.save(syncHost(name: 'local'));
      client.sync.config = const SyncConfig(
        serverUrl: 'https://unit.test',
        token: 'tok',
        passphrase: 'wrong',
      );
      await expectLater(client.sync.syncNow(), throwsA(anything));
      expect(client.sync.lastError, 'sync.error.passphrase');
      expect((await client.hosts.getByUuid('h1'))!.name, 'local');
      client.sync.config = const SyncConfig(
        serverUrl: 'https://unit.test',
        token: 'tok',
        passphrase: 'pass',
      );
      await client.sync.syncNow();
      expect((await client.hosts.getByUuid('h1'))!.updatedAt, 200);
    });

    for (final invalid in ['uuid', 'timestamp', 'schema', 'cipher']) {
      test('$invalid 损坏载荷拒绝覆盖本机数据', () async {
        await client.save(syncHost(name: 'local'));
        final host = syncHost(
          uuid: invalid == 'uuid' ? 'wrong' : 'h1',
          version: invalid == 'timestamp' ? 300 : 200,
        );
        await api.seedJson('h1', 200, {
          ...HostSyncBundle(host: host, keys: const []).toJson(),
          if (invalid == 'schema') 'version': 999,
        });
        if (invalid == 'cipher') {
          api.records['h1'] = const RemoteItemPayload(
            'h1',
            200,
            false,
            'bad-cipher',
          );
        }
        await expectLater(
          client.sync.syncNow(),
          throwsA(isA<FormatException>()),
        );
        expect((await client.hosts.getByUuid('h1'))!.name, 'local');
        expect(client.sync.syncing, isFalse);
      });
    }

    test('下载缺失载荷时报告失败，不谎报本轮同步成功', () async {
      await api.seed(syncHost());
      api.omitFetched = true;
      await expectLater(client.sync.syncNow(), throwsStateError);
      expect(client.sync.config.lastSyncAt, isNull);
    });

    test('密文被篡改时认证失败，本机已保存配置保持原值', () async {
      await client.save(syncHost(name: 'local'));
      await api.seed(syncHost(version: 200));
      final encrypted = base64Decode(api.records['h1']!.payload!.substring(3));
      encrypted[encrypted.length - 1] ^= 1;
      api.records['h1'] = RemoteItemPayload(
        'h1',
        200,
        false,
        'v1:${base64Encode(encrypted)}',
      );
      await expectLater(client.sync.syncNow(), throwsA(anything));
      expect((await client.hosts.getByUuid('h1'))!.name, 'local');
      expect(client.sync.lastError, 'sync.error.passphrase');
    });

    test('多台下载中一台失败，已成功主机保留，重试只恢复失败主机', () async {
      await api.seed(syncHost());
      await api.seedJson('h2', 100, {
        'version': 999,
        'host': syncHost(uuid: 'h2').toPortableJson(),
      });
      await expectLater(client.sync.syncNow(), throwsFormatException);
      expect((await client.hosts.getByUuid('h1'))!.syncState, SyncState.synced);
      expect(await client.hosts.getByUuid('h2'), isNull);
      expect(client.sync.config.lastSyncAt, isNull);
      await api.seed(syncHost(uuid: 'h2'));
      final report = await client.sync.syncNow();
      expect([report.pulled, report.unchanged], [1, 1]);
      expect((await client.hosts.getByUuid('h2'))!.syncState, SyncState.synced);
    });

    test('恢复主机失败时，新增密钥和分组在同一事务回滚', () async {
      final failing = SyncTestClient(
        api,
        hostFactory: _FailingHostRepository.new,
      );
      const key = KeyEntry(
        uuid: 'key-1',
        name: 'test',
        keyType: 'ssh-ed25519',
        privateKey: 'private',
        publicKey: 'public',
        createdAt: 1,
      );
      final host = syncHost().copyWith(
        authType: AuthType.key,
        keyUuid: () => key.uuid,
      );
      await api.seedJson(
        'h1',
        100,
        HostSyncBundle(
          host: host,
          groupName: 'New Group',
          keys: [key],
        ).toJson(),
      );
      (failing.hosts as _FailingHostRepository).fail = true;
      await expectLater(failing.sync.syncNow(), throwsStateError);
      expect(await failing.hosts.getByUuid('h1'), isNull);
      expect(await failing.keys.get(key.uuid), isNull);
      expect(await failing.groups.list(), isEmpty);
    });
  });

  group('同步期间的竞态', () {
    test('上传前另一端删除主机，普通上传不能将它复活', () async {
      await client.save(syncHost(version: 200));
      await api.seed(syncHost());
      api.beforePut = () async => api.tombstone('h1');
      final report = await client.sync.syncNow();
      expect(report.pushed, 0);
      expect(report.detached, 1);
      expect(api.records['h1']!.deleted, isTrue);
      expect((await client.hosts.getByUuid('h1'))!.syncState, SyncState.local);
    });
    test('索引读取后远端再次修改，下载采用最新的载荷和版本', () async {
      await api.seed(syncHost());
      api.beforeFetch = () => api.seed(syncHost(version: 200, name: 'latest'));
      await client.sync.syncNow();
      final local = (await client.hosts.getByUuid('h1'))!;
      expect(local.name, 'latest');
      expect(local.syncedAt, 200);
    });

    test('索引读取后远端删除，下载时解除本机同步', () async {
      await client.save(syncHost());
      await api.seed(syncHost(version: 200));
      api.beforeFetch = () async => api.tombstone('h1');
      final report = await client.sync.syncNow();
      expect(report.detached, 1);
      expect((await client.hosts.getByUuid('h1'))!.syncState, SyncState.local);
    });

    for (final kind in ['new', 'existing', 'local-only']) {
      test('$kind 上传时服务器并发产生更新版本，冲突后拉取最新版本', () async {
        await client.save(
          syncHost(version: 200, enabled: kind != 'local-only', name: 'local'),
        );
        if (kind != 'new') await api.seed(syncHost());
        api.beforePut = () => api.seed(syncHost(version: 300, name: 'winner'));
        final report = await client.sync.syncNow();
        expect(report.pushed, 0);
        expect(report.pulled, 1);
        expect((await client.hosts.getByUuid('h1'))!.name, 'winner');
      });
    }

    test('等待下载期间用户修改本机，较新的本机编辑不会被旧载荷覆盖', () async {
      await client.save(syncHost());
      await api.seed(syncHost(version: 200, name: 'remote'));
      api.beforeFetch = () =>
          client.save(syncHost(version: 300, name: 'user-edit'));
      final report = await client.sync.syncNow();
      expect(report.pulled, 0);
      final local = (await client.hosts.getByUuid('h1'))!;
      expect(local.name, 'user-edit');
      expect(local.syncState, SyncState.pending);
    });

    test('等待上传期间用户修改本机，成功上传旧版本后新编辑仍待同步', () async {
      await client.save(syncHost());
      api.beforePut = () =>
          client.save(syncHost(version: 200, name: 'user-edit'));
      await client.sync.syncNow();
      final local = (await client.hosts.getByUuid('h1'))!;
      expect(local.name, 'user-edit');
      expect(local.syncedAt, 100);
      expect(local.syncState, SyncState.pending);
    });

    test('同时触发两次同步，调用方等待同一任务和实际结果', () async {
      await client.save(syncHost());
      final entered = Completer<void>();
      final release = Completer<void>();
      api.beforeIndex = () async {
        entered.complete();
        await release.future;
      };
      final first = client.sync.syncNow();
      await entered.future;
      final second = client.sync.syncNow();
      release.complete();
      final reports = await Future.wait([first, second]);
      expect(identical(reports[0], reports[1]), isTrue);
      expect(reports[1].pushed, 1);
      expect(api.indexCalls, 1);
      expect(api.putCalls, 1);
    });
  });
  group('配置与自动同步', () {
    /// 带自动同步间隔的已配置参数。
    SyncConfig scheduled(int minutes) => SyncConfig(
      serverUrl: 'https://unit.test',
      token: 'tok',
      passphrase: 'pass',
      intervalMinutes: minutes,
    );

    test('保存后重新加载：地址去除空白，令牌和口令不以明文落盘', () async {
      await client.sync.saveConfig(
        const SyncConfig(
          serverUrl: '  https://sync.example:8443  ',
          token: 'secret-token',
          passphrase: 'secret-pass',
          intervalMinutes: 15,
          lastSyncAt: 42,
        ),
      );
      client.sync.stop();
      final raw = await SettingsRepository(client.db).getJson('sync.config');
      expect(raw['serverUrl'], 'https://sync.example:8443');
      expect(jsonEncode(raw), isNot(contains('secret-token')));
      expect(jsonEncode(raw), isNot(contains('secret-pass')));
      final reloaded = SyncService(
        SettingsRepository(client.db),
        client.hosts,
        client.groups,
        client.keys,
        apiFactory: (_, _) => api,
      );
      addTearDown(reloaded.dispose);
      await reloaded.load();
      reloaded.stop();
      expect(reloaded.config.serverUrl, 'https://sync.example:8443');
      expect(reloaded.config.token, 'secret-token');
      expect(reloaded.config.passphrase, 'secret-pass');
      expect(reloaded.config.intervalMinutes, 15);
      expect(reloaded.config.lastSyncAt, 42);
    });

    test('从未保存过配置时加载为未配置，不启动自动同步', () async {
      final fresh = SyncTestClient(api);
      await fresh.sync.load();
      expect(fresh.sync.config.isConfigured, isFalse);
      expect(fresh.sync.config.intervalMinutes, 0);
    });

    test('同步完成写入时间时不覆盖途中保存的新配置', () async {
      final entered = Completer<void>();
      final release = Completer<void>();
      api.beforeIndex = () async {
        entered.complete();
        await release.future;
      };
      final running = client.sync.syncNow();
      await entered.future;
      final saving = client.sync.saveConfig(
        const SyncConfig(
          serverUrl: 'https://unit.test',
          token: 'tok',
          passphrase: 'pass',
          intervalMinutes: 30,
        ),
      );
      release.complete();
      await Future.wait([running, saving]);
      client.sync.stop();
      final raw = await SettingsRepository(client.db).getJson('sync.config');
      expect(raw['interval'], 30);
      expect(raw['lastSyncAt'], client.sync.config.lastSyncAt);
    });

    test('同步途中修改服务器和口令，本轮仍只使用开始时的服务器和密钥', () async {
      final other = MemorySyncApi();
      final switching = SyncTestClient(
        api,
        apiFactory: (url, _) => url == 'https://other.test' ? other : api,
      );
      await switching.save(syncHost());
      await api.seed(syncHost(uuid: 'h2', name: 'remote'));
      api.beforeIndex = () => switching.sync.saveConfig(
        const SyncConfig(
          serverUrl: 'https://other.test',
          token: 'tok',
          passphrase: 'other',
        ),
      );
      final report = await switching.sync.syncNow();
      expect([report.pushed, report.pulled], [1, 1]);
      expect([other.indexCalls, other.putCalls, other.fetchCalls], [0, 0, 0]);
      // 能用原口令解密，说明上传未混入切换后的密钥。
      expect((await api.decoded('h1'))['host'], containsPair('uuid', 'h1'));
      expect((await switching.hosts.getByUuid('h2'))!.name, 'remote');
      expect(switching.sync.config.serverUrl, 'https://other.test');
    });

    /// 在假时钟 zone 内创建客户端并运行，服务内部的写入队列和定时器才能被假时钟推进。
    void inFakeTime(void Function(FakeAsync async, SyncTestClient c) body) {
      fakeAsync((async) => body(async, SyncTestClient(api)));
    }

    /// 推进到指定时刻后再多留一秒，让触发的同步完成内部短计时器。
    void advance(FakeAsync async, Duration d) {
      async.elapse(d);
      async.elapse(const Duration(seconds: 1));
    }

    test('按间隔自动同步，stop 后不再触发', () {
      inFakeTime((async, c) {
        c.sync.saveConfig(scheduled(5));
        advance(async, const Duration(minutes: 4));
        expect(api.indexCalls, 0);
        advance(async, const Duration(minutes: 1));
        expect(api.indexCalls, 1);
        advance(async, const Duration(minutes: 5));
        expect(api.indexCalls, 2);
        c.sync.stop();
        advance(async, const Duration(minutes: 30));
        expect(api.indexCalls, 2);
      });
    });

    test('自动同步失败只记录错误，下个周期继续重试', () {
      inFakeTime((async, c) {
        api.indexError = const SyncApiException(503, 'offline');
        c.sync.saveConfig(scheduled(1));
        advance(async, const Duration(minutes: 1));
        expect(api.indexCalls, 1);
        expect(c.sync.lastError, contains('503'));
        api.indexError = null;
        advance(async, const Duration(minutes: 1));
        expect(api.indexCalls, 2);
        expect(c.sync.lastError, isNull);
        c.sync.stop();
      });
    });

    test('退出时仍在同步，结束后不会重新启动自动同步', () {
      inFakeTime((async, c) {
        final release = Completer<void>();
        api.beforeIndex = () => release.future;
        c.sync.saveConfig(scheduled(5));
        advance(async, const Duration(minutes: 5));
        expect(api.indexCalls, 1);
        c.sync.stop();
        release.complete();
        advance(async, Duration.zero);
        expect(c.sync.syncing, isFalse);
        expect(c.sync.config.lastSyncAt, isNotNull);
        advance(async, const Duration(minutes: 30));
        expect(api.indexCalls, 1);
      });
    });

    for (final config in [scheduled(0), const SyncConfig(intervalMinutes: 5)]) {
      test(
        '间隔为 ${config.intervalMinutes} 且已配置=${config.isConfigured} 时不自动同步',
        () {
          inFakeTime((async, c) {
            c.sync.saveConfig(config);
            advance(async, const Duration(hours: 2));
            expect(api.indexCalls, 0);
          });
        },
      );
    }

    test('同步成功和失败后都通知主机列表刷新', () async {
      var changed = 0;
      client.sync.onHostsChanged = () => changed++;
      await client.sync.syncNow();
      expect(changed, 1);
      api.indexError = const SyncApiException(503, 'offline');
      await expectLater(client.sync.syncNow(), throwsA(anything));
      expect(changed, 2);
    });
  });

  group('启用、移除与依赖的补充场景', () {
    test('重新加入时服务器已有更新版本，保持待同步并在下次同步拉取', () async {
      final host = syncHost(enabled: false, name: 'local');
      await client.save(host);
      await api.seed(syncHost(version: 200, name: 'remote'));
      await client.sync.enable(host);
      expect(
        (await client.hosts.getByUuid('h1'))!.syncState,
        SyncState.pending,
      );
      expect(api.records['h1']!.updatedAt, 200);
      final report = await client.sync.syncNow();
      expect(report.pulled, 1);
      final local = (await client.hosts.getByUuid('h1'))!;
      expect(local.name, 'remote');
      expect(local.syncState, SyncState.synced);
    });

    test('未配置服务器时移除同步只改本机状态，不请求服务器', () async {
      await client.save(syncHost());
      client.sync.config = const SyncConfig();
      await client.sync.removeFromServer('h1');
      expect(api.deleteCalls, 0);
      expect((await client.hosts.getByUuid('h1'))!.syncState, SyncState.local);
    });

    test('从服务器移除从未上传的主机按成功处理，不留下删除标记', () async {
      await client.save(syncHost());
      await client.sync.removeFromServer('h1');
      expect(api.deleteCalls, 1);
      expect(api.records, isEmpty);
      expect((await client.hosts.getByUuid('h1'))!.syncState, SyncState.local);
    });

    test('引用的 SSH 密钥本机已被删除时仍可上传，拉取端保留引用不创建空密钥', () async {
      await client.save(
        syncHost().copyWith(
          authType: AuthType.key,
          keyUuid: () => 'missing-key',
        ),
      );
      expect((await client.sync.syncNow()).pushed, 1);
      final payload = await api.decoded('h1');
      expect(payload['keys'], isEmpty);
      expect(payload.containsKey('key'), isFalse);
      final other = SyncTestClient(api);
      expect((await other.sync.syncNow()).pulled, 1);
      final pulled = (await other.hosts.getByUuid('h1'))!;
      expect(pulled.keyUuid, 'missing-key');
      expect(await other.keys.get('missing-key'), isNull);
    });

    test('远端删除标记对应的仅本地主机保持不变，不计入解除', () async {
      await client.save(syncHost(enabled: false, name: 'local'));
      api.tombstone('h1');
      final report = await client.sync.syncNow();
      expect(report.detached, 0);
      expect(api.fetchCalls, 0);
      final local = (await client.hosts.getByUuid('h1'))!;
      expect(local.name, 'local');
      expect(local.syncState, SyncState.local);
    });
  });
}
