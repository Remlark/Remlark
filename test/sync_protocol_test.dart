import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:remlark/modules/sync/sync_api.dart';
import 'package:remlark/modules/sync/sync_protocol.dart';
import 'package:remlark/modules/hosts/host_model.dart';
import 'package:remlark/utils/secret_store.dart';

import 'helpers/sync_test_harness.dart';

/// 验证握手、历史协议兼容及协议不一致时阻止读写。
void main() {
  test('保存配置遇到协议不兼容时保留主机并显示协议错误，不发送数据请求', () async {
    SecretStore.initForTest(Uint8List(32));
    final paths = <String>[];
    final transport = MockClient((request) async {
      paths.add(request.url.path);
      return http.Response('{}', 426, headers: {SyncProtocol.header: '2.0'});
    });
    addTearDown(transport.close);
    final client = SyncTestClient(
      MemorySyncApi(),
      apiFactory: (url, token) => SyncApi(url, token, client: transport),
    );
    await client.save(syncHost().copyWith(syncedAt: () => 100));
    await expectLater(
      client.sync.saveConfig(client.sync.config),
      throwsA(isA<SyncProtocolException>()),
    );
    final host = (await client.hosts.getByUuid('h1'))!;
    expect(host.name, 'Ubuntu');
    expect(host.updatedAt, 100);
    expect(host.syncState, SyncState.pending);
    expect(client.sync.lastError, 'sync.error.protocol');
    expect(client.sync.config.lastSyncAt, isNull);
    expect(paths, ['/api/v1/ping']);
  });
  for (final legacy in [true, false]) {
    test('协议 1.0 客户端兼容 legacy=$legacy 服务端且会话仅握手一次', () async {
      final paths = <String>[];
      final transport = MockClient((r) async {
        paths.add(r.url.path);
        expect(r.headers[SyncProtocol.header], '1.0');
        final ping = r.url.path.endsWith('/ping');
        return http.Response(
          jsonEncode(
            ping
                ? {
                    'ok': true,
                    if (!legacy) 'protocolVersion': '1.0',
                    if (!legacy) 'supportedProtocolVersions': ['1.0', '2.0'],
                  }
                : {'items': []},
          ),
          200,
          headers: legacy ? {} : {SyncProtocol.header: '1.0'},
        );
      });
      addTearDown(transport.close);
      final api = SyncApi('https://unit.test', 'tok', client: transport);
      await api.index();
      await api.put('h1', 100, 'cipher');
      await api.delete('h1');
      expect(paths, [
        '/api/v1/ping',
        '/api/v1/items',
        '/api/v1/items/h1',
        '/api/v1/items/h1',
      ]);
    });
  }

  for (final call in <String, Future<Object?> Function(SyncApi)>{
    'ping': (api) => api.ping(),
    'index': (api) => api.index(),
    'fetch': (api) => api.fetch(['h1']),
    'put': (api) => api.put('h1', 1, 'cipher'),
    'delete': (api) => api.delete('h1'),
  }.entries) {
    for (final status in [200, 426]) {
      test('${call.key} 遇到只支持 2.0 的服务器（HTTP $status）握手后停止', () async {
        final paths = <String>[];
        final transport = MockClient((r) async {
          paths.add(r.url.path);
          return http.Response(
            '{"ok":true,"protocolVersion":"2.0"}',
            status,
            headers: {SyncProtocol.header: '2.0'},
          );
        });
        addTearDown(transport.close);
        final api = SyncApi('https://unit.test', 'tok', client: transport);
        await expectLater(
          call.value(api),
          throwsA(isA<SyncProtocolException>()),
        );
        expect(paths, ['/api/v1/ping']);
      });
    }
  }

  for (final metadata in [
    {'ok': true, 'protocolVersion': '2.0'},
    {'ok': true, 'protocolVersion': 1},
    {
      'ok': true,
      'supportedProtocolVersions': ['2.0'],
    },
    {'ok': true, 'supportedProtocolVersions': '1.0'},
    {'ok': false},
  ]) {
    test('握手元数据不兼容或格式无效时禁止写入：$metadata', () async {
      var calls = 0;
      final transport = MockClient((r) async {
        calls++;
        return http.Response(jsonEncode(metadata), 200);
      });
      addTearDown(transport.close);
      await expectLater(
        SyncApi(
          'https://unit.test',
          'tok',
          client: transport,
        ).put('h1', 1, 'cipher'),
        throwsA(isA<SyncProtocolException>()),
      );
      expect(calls, 1);
    });
  }

  test('并发入口共享握手，失败后可重试', () async {
    var probes = 0;
    final release = Completer<void>();
    final entered = Completer<void>();
    final transport = MockClient((r) async {
      if (r.url.path.endsWith('/ping')) {
        probes++;
        if (probes == 1) {
          entered.complete();
          await release.future;
          return http.Response('{}', 426);
        }
        return http.Response('{"ok":true}', 200);
      }
      return http.Response('{"items":[]}', 200);
    });
    addTearDown(transport.close);
    final api = SyncApi('https://unit.test', 'tok', client: transport);
    final first = expectLater(
      api.index(),
      throwsA(isA<SyncProtocolException>()),
    );
    await entered.future;
    final second = expectLater(
      api.ping(),
      throwsA(isA<SyncProtocolException>()),
    );
    release.complete();
    await Future.wait([first, second]);
    expect(probes, 1);
    await api.index();
    expect(probes, 2);
  });

  for (final status in [200, 409, 404]) {
    test('握手后数据响应协议变为 2.0，HTTP $status 不能被当成成功或冲突', () async {
      final transport = MockClient(
        (r) async => r.url.path.endsWith('/ping')
            ? http.Response('{"ok":true}', 200)
            : http.Response(
                '{}',
                status,
                headers: {SyncProtocol.header: '2.0'},
              ),
      );
      addTearDown(transport.close);
      final api = SyncApi('https://unit.test', 'tok', client: transport);
      await expectLater(
        api.put('h1', 1, 'cipher'),
        throwsA(isA<SyncProtocolException>()),
      );
      await expectLater(
        api.delete('h1'),
        throwsA(isA<SyncProtocolException>()),
      );
    });
  }
}
