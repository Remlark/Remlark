import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:remlark/modules/hosts/host_model.dart';
import 'package:remlark/modules/settings/settings_repository.dart';
import 'package:remlark/modules/sync/sync_api.dart';
import 'package:remlark/modules/sync/sync_config.dart';
import 'package:remlark/utils/secret_store.dart';

import 'helpers/sync_test_harness.dart';

/// 验证保存服务器配置后的状态失效、自动同步及并发边界。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SecretStore.initForTest(Uint8List(32)));

  test('删除服务器清除所有旧确认，保留同步选择、本地数据和版本', () async {
    final api = MemorySyncApi();
    final client = SyncTestClient(api);
    await client.save(syncHost().copyWith(syncedAt: () => 100));
    await client.save(syncHost(uuid: 'h2'));
    await client.save(syncHost(uuid: 'local', enabled: false));
    var refreshes = 0;
    client.sync.onHostsChanged = () => refreshes++;

    await client.sync.saveConfig(const SyncConfig());

    expect(api.indexCalls, 0);
    expect(refreshes, 1);
    final host = (await client.hosts.getByUuid('h1'))!;
    expect(host.syncState, SyncState.pending);
    expect(host.syncEnabled, isTrue);
    expect(host.syncedAt, isNull);
    expect(host.updatedAt, 100);
    expect(host.password, 'host-secret');
    expect((await client.hosts.getByUuid('h2'))!.syncState, SyncState.pending);
    expect((await client.hosts.getByUuid('local'))!.syncState, SyncState.local);
    expect(client.sync.config.lastSyncAt, isNull);
    expect(client.sync.lastReport, isNull);

    await client.sync.saveConfig(
      const SyncConfig(
        serverUrl: 'https://unit.test',
        token: 'tok',
        passphrase: 'pass',
      ),
    );
    expect(api.indexCalls, 1);
    expect(api.putCalls, 2);
    expect((await client.hosts.getByUuid('h1'))!.syncState, SyncState.synced);
  });

  for (final field in ['url', 'token', 'passphrase', 'unchanged']) {
    test('保存 $field 配置且服务器离线时旧已同步标记失效，配置仍落盘', () async {
      final api = MemorySyncApi();
      final client = SyncTestClient(api);
      await client.save(syncHost().copyWith(syncedAt: () => 100));
      api.indexError = const SyncApiException(503, 'offline');
      final config = SyncConfig(
        serverUrl: field == 'url' ? 'https://other.test' : 'https://unit.test',
        token: field == 'token' ? 'other-token' : 'tok',
        passphrase: field == 'passphrase' ? 'other-pass' : 'pass',
      );
      await expectLater(
        client.sync.saveConfig(config),
        throwsA(isA<SyncApiException>()),
      );
      expect(api.indexCalls, 1);
      expect(
        (await client.hosts.getByUuid('h1'))!.syncState,
        SyncState.pending,
      );
      expect(client.sync.lastError, contains('503'));
      expect(client.sync.config.lastSyncAt, isNull);
      final stored = await SettingsRepository(client.db).getJson('sync.config');
      expect(stored['serverUrl'], config.serverUrl);
      // 失败后保存队列仍能正常删除配置。
      await client.sync.saveConfig(const SyncConfig());
      expect(client.sync.lastError, isNull);
    });
  }

  test('更换服务器后验证同版本内容，上传缺失主机并处理删除标记', () async {
    final old = MemorySyncApi();
    final other = MemorySyncApi();
    final client = SyncTestClient(
      old,
      apiFactory: (url, _) => url == 'https://other.test' ? other : old,
    );
    for (final uuid in ['same', 'missing', 'deleted']) {
      await client.save(syncHost(uuid: uuid).copyWith(syncedAt: () => 100));
    }
    await client.save(syncHost(uuid: 'local', enabled: false));
    await other.seed(syncHost(uuid: 'same', name: 'new-server-content'));
    other.tombstone('deleted');
    await client.sync.saveConfig(
      const SyncConfig(
        serverUrl: 'https://other.test',
        token: 'tok',
        passphrase: 'pass',
      ),
    );
    expect(old.indexCalls, 0);
    expect(other.indexCalls, 1);
    expect(other.putCalls, 1);
    expect(other.fetchCalls, 1);
    final same = (await client.hosts.getByUuid('same'))!;
    expect(same.name, 'new-server-content');
    expect(same.syncState, SyncState.synced);
    expect(
      (await client.hosts.getByUuid('missing'))!.syncState,
      SyncState.synced,
    );
    expect(
      (await client.hosts.getByUuid('deleted'))!.syncState,
      SyncState.local,
    );
    expect((await client.hosts.getByUuid('local'))!.syncState, SyncState.local);
  });

  test('保存后部分上传失败，仅已确认的主机显示已同步', () async {
    final api = MemorySyncApi();
    final client = SyncTestClient(api);
    for (final uuid in ['h1', 'h2']) {
      await client.save(syncHost(uuid: uuid).copyWith(syncedAt: () => 100));
    }
    api.beforePut = () async {
      if (api.putCalls == 2) {
        api.putError = const SyncApiException(503, 'offline');
      }
    };
    await expectLater(
      client.sync.saveConfig(client.sync.config),
      throwsA(anything),
    );
    final states = await Future.wait(['h1', 'h2'].map(client.hosts.getByUuid));
    expect(states.where((h) => h!.syncState == SyncState.synced).length, 1);
    expect(states.where((h) => h!.syncState == SyncState.pending).length, 1);
  });

  test('同步中删除服务器，等待旧轮次后清除旧响应写入的确认状态', () async {
    final api = MemorySyncApi();
    final client = SyncTestClient(api);
    await client.save(syncHost());
    final entered = Completer<void>();
    final release = Completer<void>();
    api.beforePut = () async {
      entered.complete();
      await release.future;
    };
    final running = client.sync.syncNow();
    await entered.future;
    final saving = client.sync.saveConfig(const SyncConfig());
    release.complete();
    await Future.wait([running, saving]);
    expect((await client.hosts.getByUuid('h1'))!.syncState, SyncState.pending);
    expect(client.sync.config.lastSyncAt, isNull);
    expect(client.sync.lastReport, isNull);
  });

  test('单台上传等待响应时删除服务器，旧响应不能恢复已同步标记', () async {
    final api = MemorySyncApi();
    final client = SyncTestClient(api);
    final host = syncHost(enabled: false);
    await client.save(host);
    final entered = Completer<void>();
    final release = Completer<void>();
    api.beforePut = () async {
      entered.complete();
      await release.future;
    };
    final enabling = client.sync.enable(host);
    await entered.future;
    await client.sync.saveConfig(const SyncConfig());
    release.complete();
    await enabling;
    expect((await client.hosts.getByUuid('h1'))!.syncState, SyncState.pending);
  });
}
