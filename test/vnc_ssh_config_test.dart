import 'package:flutter_test/flutter_test.dart';
import 'package:remlark/modules/hosts/host_model.dart';
import 'package:remlark/modules/hosts/ui/host_form.dart';
import 'package:remlark/modules/hosts/vnc_ssh_config.dart';

/// 创建带共用账户的 VNC 测试主机。
HostEntry _vnc(Map<String, dynamic> extra) => HostEntry(
  uuid: 'v',
  protocol: HostProtocol.vnc,
  name: 'mac',
  address: '192.168.0.88',
  port: 5900,
  username: 'u',
  password: 'pw',
  savePassword: true,
  hostKeyFingerprint: 'SHA256:x',
  extra: extra,
  updatedAt: 0,
  createdAt: 0,
);

void main() {
  test('内置 SSH 配置：读写往返；转换为 SSH 主机时沿用 uuid、地址、用户名、密码', () {
    final extra = <String, dynamic>{};
    const VncSshConfig(enabled: true, port: 2222, authType: AuthType.key, keyUuid: 'k').writeTo(extra);
    final h = _vnc(extra);
    final c = h.vncSsh!;
    expect((c.port, c.authType, c.keyUuid), (2222, AuthType.key, 'k'));
    final ssh = h.asSshHost(c);
    expect(
      (ssh.uuid, ssh.protocol, ssh.address, ssh.port, ssh.username, ssh.password),
      ('v', HostProtocol.ssh, '192.168.0.88', 2222, 'u', 'pw'),
    );
    expect((ssh.authType, ssh.keyUuid, ssh.proxy.enabled), (AuthType.key, 'k', false));
    expect(ssh.jumpChain, isEmpty);
    expect(ssh.hostKeyFingerprint, 'SHA256:x', reason: 'SSH 主机指纹记录在本主机');
    // 未启用 / 未配置
    expect(_vnc({}).vncSsh, isNull);
    final off = <String, dynamic>{};
    const VncSshConfig().writeTo(off);
    expect(_vnc(off).vncSsh, isNull);
  });

  test('编辑表单：新建 VNC 主机仅启用 VNC；旧版关联 SSH 主机迁移为内置配置并移除旧字段', () {
    final fresh = HostForm(null, HostProtocol.vnc, null);
    fresh.address.text = '10.0.0.1';
    final built = fresh.build();
    expect(built.vncSsh, isNull);

    final legacy = _vnc({'transferHost': 's1'});
    final linked = HostEntry(
      uuid: 's1',
      protocol: HostProtocol.ssh,
      name: 'mac-ssh',
      address: '192.168.0.88',
      port: 2200,
      username: 'u',
      authType: AuthType.key,
      keyUuid: 'k1',
      updatedAt: 0,
      createdAt: 0,
    );
    final f = HostForm(legacy, HostProtocol.vnc, null)..migrateLegacySsh(linked);
    final saved = f.build();
    expect(saved.extra.containsKey('transferHost'), isFalse);
    final c = saved.vncSsh!;
    expect((c.port, c.authType, c.keyUuid), (2200, AuthType.key, 'k1'));
    // 已有内置配置时不迁移
    final both = HostForm(
      _vnc({
        'transferHost': 's1',
        'ssh': {'enabled': false, 'port': 22},
      }),
      HostProtocol.vnc,
      null,
    )..migrateLegacySsh(linked);
    expect(both.build().vncSsh, isNull);
  });
  test('不兼容的旧关联在编辑保存后仍可使用，主动启用内置 SSH 才替换', () {
    final host = _vnc({'transferHost': 'old'});
    final linked = host.copyWith(protocol: HostProtocol.ssh, username: 'other');
    final form = HostForm(host, HostProtocol.vnc, null)..migrateLegacySsh(linked);
    addTearDown(form.dispose);
    expect(form.preserveLegacySsh, isTrue);
    expect(form.build().legacyTransferHost, 'old');
    form.vncSsh = VncSshConfig.defaults;
    expect(form.build().legacyTransferHost, isNull);
    expect(form.build().vncSsh, isNotNull);
  });

  test('内置 SSH 显式关闭时不回退到残留旧关联', () {
    final host = _vnc({
      'transferHost': 'old',
      'ssh': {'enabled': false},
    });
    expect(host.vncSsh, isNull);
    expect(host.legacyTransferHost, isNull);
  });

  test('VNC 单独使用及内置 SSH 参数校验', () {
    final form = HostForm(null, HostProtocol.vnc, null);
    addTearDown(form.dispose);
    form.address.text = 'mac.local';
    form.setProtocol(HostProtocol.vnc);
    form.setSshEnabled(true);
    expect(form.validate(), 'vnc.ssh.username.required');
    form.username.text = 'user';
    form.sshPort.text = '65536';
    expect(form.validate(), 'vnc.ssh.port.invalid');
    form.sshPort.text = '2222';
    form.vncSsh = form.vncSsh.copyWith(authType: AuthType.key);
    expect(form.validate(), 'auth.key.required');
    form.vncSsh = form.vncSsh.copyWith(keyUuid: () => 'key');
    expect(form.validate(), isNull);
    final restored = HostEntry.fromPortableJson(form.build().toPortableJson());
    expect(restored.vncSsh?.keyUuid, 'key');
    form.vncSsh = form.vncSsh.copyWith(enabled: false);
    form.username.clear();
    form.sshPort.clear();
    expect(form.validate(), isNull);
    expect(form.build().vncSsh, isNull);
    form.port.text = '0';
    expect(form.validate(), 'host.port.invalid');
  });
  test('已有 SSH 增加 VNC 后保留身份、端口、认证、跳板与代理，可独立连接两种协议', () {
    final original = _vnc({}).copyWith(
      protocol: HostProtocol.ssh,
      port: 2200,
      authType: AuthType.key,
      keyUuid: () => 'key',
      jumpChain: ['jump'],
      proxy: const ProxyConfig(type: ProxyType.socks5, host: 'proxy', port: 1080),
    );
    final form = HostForm(original, HostProtocol.ssh, null);
    addTearDown(form.dispose);
    form.setProtocol(HostProtocol.vnc);
    form.setSshEnabled(true);
    form.port.text = '5901';
    final combined = form.build();
    expect(combined.uuid, original.uuid);
    expect(combined.connectionProtocols, [HostProtocol.ssh, HostProtocol.vnc]);
    final terminal = combined.forConnection(HostProtocol.ssh);
    expect(terminal.port, 2200);
    expect(terminal.keyUuid, 'key');
    expect(terminal.jumpChain, ['jump']);
    expect(terminal.proxy.port, 1080);
    expect(combined.forConnection(HostProtocol.vnc).port, 5901);
    form.setProtocol(HostProtocol.ssh);
    expect(form.build().port, 2200);
    expect(form.build().connectionProtocols, [HostProtocol.ssh]);
    form.setProtocol(HostProtocol.vnc);
    form.setSshEnabled(true);
    expect(form.build().port, 5901);
    form.setSshEnabled(false);
    expect(form.build().connectionProtocols, [HostProtocol.vnc]);
    expect(() => form.build().forConnection(HostProtocol.ssh), throwsStateError);
  });
}
