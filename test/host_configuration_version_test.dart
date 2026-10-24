import 'dart:typed_data';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:remlark/data/database.dart';
import 'package:remlark/modules/hosts/host_model.dart';
import 'package:remlark/modules/hosts/host_repository.dart';
import 'package:remlark/modules/hosts/vnc_ssh_config.dart';
import 'package:remlark/utils/secret_store.dart';

import 'helpers/sync_test_harness.dart';

void main() {
  late HostRepository hosts;
  setUp(() {
    SecretStore.initForTest(Uint8List(32));
    final db = AppDatabase(NativeDatabase.memory());
    hosts = HostRepository(db);
    addTearDown(db.close);
  });

  for (var bits = 1; bits < 8; bits++) {
    final protocols = {
      for (var i = 0; i < 3; i++)
        if ((bits & (1 << i)) != 0) HostProtocol.values[i],
    };
    test('协议组合 $bits：连接、系统探测和指纹回写不改变配置修改时间', () async {
      final host = protocolHost(protocols);
      await hosts.save(host, touch: false);
      await hosts.setSyncState(host.uuid, enabled: true, syncedAt: 100);
      await hosts.touchConnected(host.uuid);
      await hosts.touchConnected(host.uuid);
      await hosts.updateOs(host.uuid, 'ubuntu', 'Ubuntu 24.04');
      for (final protocol in protocols) {
        await hosts.updateFingerprint(
          host.uuid,
          'fp-${protocol.name}',
          protocol: protocol,
        );
      }
      final after = (await hosts.getByUuid(host.uuid))!;
      expect(after.updatedAt, 100);
      expect(after.syncedAt, 100);
      expect(after.syncState, SyncState.synced);
      expect(after.lastConnectedAt, isNotNull);
      expect(after.osId, 'ubuntu');
      for (final protocol in protocols) {
        expect(
          after.forConnection(protocol).hostKeyFingerprint,
          'fp-${protocol.name}',
        );
      }
    });
  }

  test('相同用户名或已记住密码重复回写不产生新配置版本', () async {
    final host = protocolHost(HostProtocol.values.toSet());
    await hosts.save(host, touch: false);
    await hosts.setSyncState(host.uuid, enabled: true, syncedAt: 100);
    await hosts.updateUsername(host.uuid, host.username);
    for (final protocol in host.connectionProtocols) {
      await hosts.updatePassword(
        host.uuid,
        host.forConnection(protocol).password,
        true,
        protocol: protocol,
      );
    }
    final after = (await hosts.getByUuid(host.uuid))!;
    expect(after.updatedAt, 100);
    expect(after.syncState, SyncState.synced);
  });

  for (final protocol in HostProtocol.values) {
    test('修改 ${protocol.name} 保存密码属于配置变更，连接本身不改变新版本', () async {
      final host = protocolHost(HostProtocol.values.toSet());
      await hosts.save(host, touch: false);
      await hosts.setSyncState(host.uuid, enabled: true, syncedAt: 100);
      await hosts.updatePassword(
        host.uuid,
        'changed-secret',
        true,
        protocol: protocol,
      );
      final edited = (await hosts.getByUuid(host.uuid))!;
      expect(edited.updatedAt, greaterThan(100));
      expect(edited.syncState, SyncState.pending);
      expect(edited.forConnection(protocol).password, 'changed-secret');
      await hosts.touchConnected(host.uuid);
      final connected = (await hosts.getByUuid(host.uuid))!;
      expect(connected.updatedAt, edited.updatedAt);
      expect(connected.syncState, SyncState.pending);
    });
  }

  test('修改用户名产生新版本，取消记住密码只在配置实际改变时更新版本', () async {
    final host = protocolHost(HostProtocol.values.toSet());
    await hosts.save(host, touch: false);
    await hosts.updateUsername(host.uuid, 'new-user');
    final usernameEdited = (await hosts.getByUuid(host.uuid))!;
    expect(usernameEdited.updatedAt, greaterThan(100));
    await hosts.updatePassword(
      host.uuid,
      null,
      false,
      protocol: HostProtocol.rdp,
    );
    final cleared = (await hosts.getByUuid(host.uuid))!;
    expect(cleared.updatedAt, greaterThan(usernameEdited.updatedAt));
    expect(cleared.forConnection(HostProtocol.rdp).password, isNull);
    await hosts.updatePassword(
      host.uuid,
      null,
      false,
      protocol: HostProtocol.rdp,
    );
    expect((await hosts.getByUuid(host.uuid))!.updatedAt, cleared.updatedAt);
  });
}
