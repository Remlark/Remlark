import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:remlark/modules/hosts/host_model.dart';
import 'package:remlark/modules/proxies/proxy_connection_test.dart';
import 'package:remlark/utils/async_byte_reader.dart';
import 'package:remlark/utils/network_endpoint.dart';

/// 多平台测试 P-17：三平台真实本地 Socket 的代理握手、认证、超时及取消。
void main() {
  /// 创建本地代理夹具，所有检测仅连接回环地址，不依赖外部网络。
  Future<ServerSocket> server(Future<void> Function(Socket) handler) async {
    final listener = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    final clients = <Socket>[];
    listener.listen((client) {
      clients.add(client);
      unawaited(handler(client));
    });
    addTearDown(() async {
      for (final client in clients) {
        client.destroy();
      }
      await listener.close();
    });
    return listener;
  }

  test('解析测试目标：域名、IPv4、IPv6、端口范围及 URL/认证信息拒绝', () {
    expect(NetworkEndpoint.tryParse(' example.com:443 ')!.host, 'example.com');
    expect(NetworkEndpoint.tryParse('127.0.0.1:22')!.port, 22);
    final ipv6 = NetworkEndpoint.tryParse('[::1]:443');
    expect(ipv6, isNotNull);
    expect(ipv6!.host, '::1');
    for (final invalid in [
      'example.com',
      'example.com:0',
      'host:65536',
      'host:abc',
      'https://example.com:443',
      'u:p@host:443',
      'host:443/path',
      'host:443?x=1',
      'bad host:443',
    ]) {
      expect(NetworkEndpoint.tryParse(invalid), isNull, reason: invalid);
    }
  });

  test('HTTP CONNECT 验证目标及认证，连接成功后主动释放资源', () async {
    String? header;
    final listener = await server((client) async {
      final reader = AsyncByteReader(client);
      header = utf8.decode(await reader.readUntil(utf8.encode('\r\n\r\n')));
      client.add(utf8.encode('HTTP/1.1 200 Connection Established\r\n\r\n'));
    });
    final test = SocketProxyConnectionTest();
    addTearDown(test.cancel);
    final result = await test.check(
      ProxyConfig(
        type: ProxyType.http,
        host: '127.0.0.1',
        port: listener.port,
        username: 'u',
        password: 'p',
      ),
      const NetworkEndpoint('example.com', 443),
    );
    expect(result.status, ProxyTestStatus.success);
    expect(header, contains('CONNECT example.com:443 HTTP/1.1'));
    expect(
      header,
      contains(
        'Proxy-Authorization: Basic ${base64Encode(utf8.encode('u:p'))}',
      ),
    );
  });

  test('HTTP 407 是认证失败，普通 TCP 服务不是可用代理', () async {
    for (final response in [
      'HTTP/1.1 407 Auth Required\r\n\r\n',
      'NOT_HTTP 200 OK\r\n\r\n',
    ]) {
      final listener = await server((client) async {
        await AsyncByteReader(client).readUntil(utf8.encode('\r\n\r\n'));
        client.add(utf8.encode(response));
      });
      final test = SocketProxyConnectionTest();
      final result = await test.check(
        ProxyConfig(
          type: ProxyType.http,
          host: '127.0.0.1',
          port: listener.port,
        ),
        const NetworkEndpoint('example.com', 443),
      );
      expect(
        result.status,
        response.contains('407')
            ? ProxyTestStatus.authentication
            : ProxyTestStatus.protocol,
      );
      test.cancel();
    }
  });

  test('SOCKS5 完成协商、用户名密码认证及目标连接，错误密码明确失败', () async {
    for (final valid in [true, false]) {
      String? target;
      final listener = await server((client) async {
        final reader = AsyncByteReader(client);
        final greeting = await reader.read(2);
        await reader.read(greeting[1]);
        client.add([5, 2]);
        expect(await reader.u8(), 1);
        final user = utf8.decode(await reader.read(await reader.u8()));
        final password = utf8.decode(await reader.read(await reader.u8()));
        expect((user, password), ('user', valid ? 'password' : 'wrong'));
        client.add([1, valid ? 0 : 1]);
        if (!valid) return;
        expect(await reader.read(4), [5, 1, 0, 3]);
        target = utf8.decode(await reader.read(await reader.u8()));
        expect(await reader.u16(), 443);
        client.add([5, 0, 0, 1, 127, 0, 0, 1, 0, 1]);
      });
      final test = SocketProxyConnectionTest();
      final result = await test.check(
        ProxyConfig(
          type: ProxyType.socks5,
          host: '127.0.0.1',
          port: listener.port,
          username: 'user',
          password: valid ? 'password' : 'wrong',
        ),
        const NetworkEndpoint('example.com', 443),
      );
      expect(
        result.status,
        valid ? ProxyTestStatus.success : ProxyTestStatus.authentication,
      );
      if (valid) expect(target, 'example.com');
      test.cancel();
    }
  });

  test('无响应代理在总超时内结束，慢速零碎响应也不能无限延长', () async {
    final timers = <Timer>[];
    addTearDown(() {
      for (final timer in timers) {
        timer.cancel();
      }
    });
    for (final trickle in [false, true]) {
      final listener = await server((client) async {
        client.listen((_) {});
        if (trickle) {
          timers.add(
            Timer.periodic(
              const Duration(milliseconds: 15),
              (_) => client.add([65]),
            ),
          );
        }
      });
      final test = SocketProxyConnectionTest(
        timeout: const Duration(milliseconds: 100),
      );
      final watch = Stopwatch()..start();
      final result = await test.check(
        ProxyConfig(
          type: ProxyType.http,
          host: '127.0.0.1',
          port: listener.port,
        ),
        const NetworkEndpoint('example.com', 443),
      );
      expect(result.status, ProxyTestStatus.timeout);
      expect(watch.elapsed, lessThan(const Duration(seconds: 2)));
      for (final timer in timers) {
        timer.cancel();
      }
      test.cancel();
    }
  });

  test('SOCKS5 非法版本或非法连接响应不能误判为通过', () async {
    for (final badGreeting in [true, false]) {
      final listener = await server((client) async {
        final reader = AsyncByteReader(client);
        final greeting = await reader.read(2);
        await reader.read(greeting[1]);
        client.add([badGreeting ? 4 : 5, 0]);
        if (badGreeting) return;
        await reader.read(4);
        await reader.read(await reader.u8());
        await reader.u16();
        client.add([4, 0, 0, 1, 127, 0, 0, 1, 0, 1]);
      });
      final probe = SocketProxyConnectionTest();
      final result = await probe.check(
        ProxyConfig(
          type: ProxyType.socks5,
          host: '127.0.0.1',
          port: listener.port,
        ),
        const NetworkEndpoint('example.com', 443),
      );
      expect(result.status, ProxyTestStatus.protocol);
      probe.cancel();
    }
  });

  test('取消检测立即关闭握手连接，旧结果不会当作成功', () async {
    final accepted = Completer<void>();
    final disconnected = Completer<void>();
    final listener = await server((client) async {
      client.listen(
        (_) {},
        onDone: () {
          if (!disconnected.isCompleted) disconnected.complete();
        },
      );
      accepted.complete();
    });
    final test = SocketProxyConnectionTest();
    final pending = test.check(
      ProxyConfig(
        type: ProxyType.socks5,
        host: '127.0.0.1',
        port: listener.port,
      ),
      const NetworkEndpoint('example.com', 443),
    );
    await accepted.future;
    test.cancel();
    expect(
      (await pending.timeout(const Duration(seconds: 1))).status,
      ProxyTestStatus.cancelled,
    );
    await disconnected.future.timeout(const Duration(seconds: 1));
  });

  test('未启用的代理不允许以直连伪装测试通过', () async {
    final test = SocketProxyConnectionTest();
    expect(
      (await test.check(
        const ProxyConfig(),
        const NetworkEndpoint('example.com', 443),
      )).status,
      ProxyTestStatus.invalid,
    );
  });

  test('IPv6 测试目标使用正确的 HTTP authority 和 SOCKS5 地址类型', () async {
    for (final type in [ProxyType.http, ProxyType.socks5]) {
      final listener = await server((client) async {
        final reader = AsyncByteReader(client);
        if (type == ProxyType.http) {
          final header = utf8.decode(
            await reader.readUntil(utf8.encode('\r\n\r\n')),
          );
          expect(header, contains('CONNECT [::1]:443 HTTP/1.1'));
          client.add(utf8.encode('HTTP/1.1 200 OK\r\n\r\n'));
        } else {
          final greeting = await reader.read(2);
          await reader.read(greeting[1]);
          client.add([5, 0]);
          expect(await reader.read(4), [5, 1, 0, 4]);
          expect(await reader.read(16), InternetAddress('::1').rawAddress);
          expect(await reader.u16(), 443);
          client.add([5, 0, 0, 1, 127, 0, 0, 1, 0, 1]);
        }
      });
      final probe = SocketProxyConnectionTest();
      expect(
        (await probe.check(
          ProxyConfig(type: type, host: '127.0.0.1', port: listener.port),
          const NetworkEndpoint('::1', 443),
        )).status,
        ProxyTestStatus.success,
      );
      probe.cancel();
    }
  });
}
