import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:remlark/data/database.dart';
import 'package:remlark/modules/hosts/host_model.dart';
import 'package:remlark/modules/hosts/host_repository.dart';
import 'package:remlark/modules/hosts/vnc_ssh_config.dart';
import 'package:remlark/modules/proxies/proxy_profile.dart';
import 'package:remlark/modules/proxies/proxy_repository.dart';
import 'package:remlark/utils/crypto_utils.dart';
import 'package:remlark/utils/secret_store.dart';

/// 多平台测试 P-16：三平台共用代理存储、SSH/RDP 选择和双协议配置解析。
void main() {
  test('SSH、RDP、VNC 内置 SSH 均复用共享配置，重连解析新参数且端口不混用', () async {
    SecretStore.initForTest(CryptoUtils.randomBytes(32));
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    final hosts = HostRepository(db);
    final proxies = ProxyRepository(db);
    const socks = ProxyConfig(
      type: ProxyType.socks5,
      host: '127.0.0.1',
      port: 1080,
      username: 'u',
      password: 'p',
    );
    await proxies.save(
      const ProxyEntry(uuid: 'shared', name: 'Shared', config: socks),
    );
    final entries = <HostEntry>[];
    for (final protocol in HostProtocol.values) {
      final saved = await hosts.save(
        HostEntry(
          uuid: protocol.name,
          name: protocol.name,
          protocol: protocol,
          address: '192.0.2.1',
          port: protocol.defaultPort,
          proxyUuid: 'shared',
          createdAt: 1,
          updatedAt: 1,
          extra: protocol == HostProtocol.vnc
              ? {
                  'ssh': {'enabled': true, 'port': 2222},
                }
              : const {},
        ),
      );
      entries.add(
        protocol == HostProtocol.vnc
            ? saved.forConnection(HostProtocol.ssh)
            : saved,
      );
    }
    expect(await proxies.usageCounts(), {'shared': 3});
    const http = ProxyConfig(
      type: ProxyType.http,
      host: 'office.example.com',
      port: 8080,
      username: 'new',
      password: 'new-secret',
    );
    await proxies.save(
      const ProxyEntry(uuid: 'shared', name: 'Changed', config: http),
    );
    for (final entry in entries) {
      final resolved = await hosts.resolveProxy(entry);
      expect(resolved.proxy.toJson(), http.toJson());
      expect(resolved.port, entry.port);
      expect(entry.proxy.toJson(), socks.toJson(), reason: '已有会话的配置快照保持不变');
    }
    expect(entries.last.port, 2222);
    expect(await proxies.delete('shared'), isFalse);
  });
}
