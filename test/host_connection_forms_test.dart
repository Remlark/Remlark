import 'dart:typed_data';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:remlark/data/database.dart';
import 'package:remlark/modules/hosts/host_model.dart';
import 'package:remlark/modules/hosts/host_repository.dart';
import 'package:remlark/modules/hosts/ui/host_connection_forms.dart';
import 'package:remlark/modules/hosts/vnc_ssh_config.dart';
import 'package:remlark/utils/secret_store.dart';

void main() {
  test('一条主机可同时保存三种协议的独立端口与凭据', () {
    final forms = HostConnectionForms(null, HostProtocol.ssh, null);
    addTearDown(forms.dispose);
    forms.current.name.text = 'server';
    forms.current.address.text = 'host.example';
    forms.current.username.text = 'ssh-user';
    forms.current.password.text = 'ssh-secret';
    forms.current.port.text = '2222';
    forms.enabled.addAll({HostProtocol.vnc, HostProtocol.rdp});
    forms.select(HostProtocol.vnc);
    forms.current.username.text = 'vnc-user';
    forms.current.password.text = 'vnc-secret';
    forms.current.port.text = '5901';
    forms.select(HostProtocol.rdp);
    forms.current.username.text = 'rdp-user';
    forms.current.password.text = 'rdp-secret';
    forms.current.port.text = '3390';
    forms.osOverride = 'ubuntu';

    expect(forms.validate(), isNull);
    final host = forms.build();
    expect(host.connectionProtocols, HostProtocol.values);
    expect(host.protocol, HostProtocol.vnc);
    expect(host.vncSsh, isNotNull);
    expect(
      host.forConnection(HostProtocol.ssh).endpoint,
      'ssh-user@host.example:2222',
    );
    expect(
      host.forConnection(HostProtocol.rdp).endpoint,
      'rdp-user@host.example:3390',
    );
    expect(host.forConnection(HostProtocol.rdp).password, 'rdp-secret');
    expect(host.forConnection(HostProtocol.vnc).password, 'vnc-secret');
    expect(host.forConnection(HostProtocol.rdp).extra['osOverride'], 'ubuntu');
    final portable = HostEntry.fromPortableJson(host.toPortableJson());
    expect(portable.forConnection(HostProtocol.ssh).password, 'ssh-secret');
    final reopened = HostConnectionForms(portable, HostProtocol.ssh, null);
    addTearDown(reopened.dispose);
    expect(reopened.validate(), isNull);
    final redacted = host.toPortableJson(withSecrets: false);
    final profiles = (redacted['extra'] as Map)['connections'] as Map;
    expect((profiles['ssh'] as Map).containsKey('password'), isFalse);
    expect((profiles['rdp'] as Map).containsKey('password'), isFalse);
  });

  test('编辑时移除协议，不遗留连接入口', () {
    final forms = HostConnectionForms(null, HostProtocol.ssh, null);
    addTearDown(forms.dispose);
    forms.current.address.text = 'host.example';
    forms.enabled.addAll({HostProtocol.vnc, HostProtocol.rdp});
    forms.select(HostProtocol.vnc);
    final previous = forms.build();
    final edit = HostConnectionForms(previous, HostProtocol.ssh, null);
    addTearDown(edit.dispose);
    edit.enabled.remove(HostProtocol.rdp);
    expect(edit.build().connectionProtocols, [
      HostProtocol.ssh,
      HostProtocol.vnc,
    ]);
    edit.enabled.remove(HostProtocol.ssh);
    expect(edit.build().connectionProtocols, [HostProtocol.vnc]);
  });

  test('手动系统图标随主机编辑保存，可恢复自动识别', () {
    final forms = HostConnectionForms(null, HostProtocol.rdp, null);
    addTearDown(forms.dispose);
    forms.current.address.text = 'ubuntu.example';
    forms.osOverride = 'ubuntu';
    final saved = forms.build();
    expect(saved.extra['osOverride'], 'ubuntu');
    final reopened = HostConnectionForms(saved, HostProtocol.rdp, null);
    addTearDown(reopened.dispose);
    expect(reopened.osOverride, 'ubuntu');
    reopened.osOverride = null;
    expect(reopened.build().extra.containsKey('osOverride'), isFalse);
  });

  test('附加协议凭据加密存储，记住密码只更新对应协议', () async {
    SecretStore.initForTest(Uint8List(32));
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    final repo = HostRepository(db);
    final forms = HostConnectionForms(null, HostProtocol.vnc, null);
    addTearDown(forms.dispose);
    forms.current.address.text = 'host.example';
    forms.current.password.text = 'vnc-secret';
    forms.enabled.add(HostProtocol.rdp);
    forms.select(HostProtocol.rdp);
    forms.current.password.text = 'rdp-secret';
    final saved = await repo.save(forms.build());
    final raw = await db.select(db.hosts).getSingle();
    expect(raw.extraJson, isNot(contains('rdp-secret')));
    expect(raw.extraJson, isNot(contains('vnc-secret')));
    expect(saved.forConnection(HostProtocol.rdp).password, 'rdp-secret');
    await repo.updatePassword(
      saved.uuid,
      'new-rdp-secret',
      true,
      protocol: HostProtocol.rdp,
    );
    await repo.updateFingerprint(
      saved.uuid,
      'rdp-fingerprint',
      protocol: HostProtocol.rdp,
    );
    final updated = (await repo.getByUuid(saved.uuid))!;
    expect(updated.forConnection(HostProtocol.rdp).password, 'new-rdp-secret');
    expect(
      updated.forConnection(HostProtocol.rdp).hostKeyFingerprint,
      'rdp-fingerprint',
    );
    expect(updated.forConnection(HostProtocol.vnc).password, 'vnc-secret');
    expect(updated.forConnection(HostProtocol.vnc).hostKeyFingerprint, isNull);
  });
}
