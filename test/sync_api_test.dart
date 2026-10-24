import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:remlark/modules/sync/sync_api.dart';

/// 普通接口测试使用兼容的握手，协议差异由独立测试覆盖。
MockClient _syncClient(Future<http.Response> Function(http.Request) handle) =>
    MockClient((request) async {
      if (request.url.path.endsWith('/ping')) {
        return http.Response('{"ok":true}', 200);
      }
      return handle(request);
    });

void main() {
  test('索引请求规范化地址并携带认证，保留版本和删除状态', () async {
    final transport = _syncClient((request) async {
      expect(request.url.toString(), 'https://sync.example/base/api/v1/items');
      expect(request.headers['Authorization'], 'Bearer token');
      expect(request.method, 'GET');
      return http.Response(
        jsonEncode({
          'items': [
            {'uuid': 'h1', 'updatedAt': 123, 'deleted': false},
            {'uuid': 'h2', 'updatedAt': 456, 'deleted': true},
          ],
        }),
        200,
      );
    });
    addTearDown(transport.close);
    final items = await SyncApi(
      ' https://sync.example/base/ ',
      'token',
      client: transport,
    ).index();
    expect(items['h1']!.updatedAt, 123);
    expect(items['h2']!.deleted, isTrue);
  });

  test('下载使用同一响应中的密文版本，同时保留删除记录', () async {
    final transport = _syncClient((request) async {
      expect(request.method, 'POST');
      expect((jsonDecode(request.body) as Map)['uuids'], ['h1', 'h2']);
      return http.Response(
        jsonEncode({
          'items': [
            {
              'uuid': 'h1',
              'updatedAt': 200,
              'deleted': false,
              'payload': 'cipher',
            },
            {'uuid': 'h2', 'updatedAt': 300, 'deleted': true},
          ],
        }),
        200,
      );
    });
    addTearDown(transport.close);
    final items = await SyncApi(
      'https://sync.example',
      'token',
      client: transport,
    ).fetch(['h1', 'h2']);
    expect(items['h1']!.updatedAt, 200);
    expect(items['h1']!.payload, 'cipher');
    expect(items['h2']!.deleted, isTrue);
    expect(items['h2']!.payload, isNull);
  });

  test('空下载不请求网络，超过 1000 台去重后分批', () async {
    final batchSizes = <int>[];
    final transport = _syncClient((request) async {
      final ids = (jsonDecode(request.body) as Map)['uuids'] as List;
      batchSizes.add(ids.length);
      return http.Response(
        jsonEncode({
          'items': [
            for (final id in ids)
              {
                'uuid': id,
                'updatedAt': 100,
                'deleted': false,
                'payload': 'cipher',
              },
          ],
        }),
        200,
      );
    });
    addTearDown(transport.close);
    final api = SyncApi('https://sync.example', 'token', client: transport);
    expect(await api.fetch([]), isEmpty);
    expect(batchSizes, isEmpty);
    final items = await api.fetch([
      for (var i = 0; i < 1001; i++) 'host-$i',
      'host-0',
    ]);
    expect(items.length, 1001);
    expect(batchSizes, [1000, 1]);
  });

  for (final status in [200, 409, 401, 503]) {
    test('上传 HTTP $status 正确区分成功、版本冲突和服务失败', () async {
      final transport = _syncClient((request) async {
        expect(request.method, 'PUT');
        expect((jsonDecode(request.body) as Map), {
          'updatedAt': 100,
          'payload': 'cipher',
          'restoreDeleted': false,
        });
        return http.Response('response', status);
      });
      addTearDown(transport.close);
      final api = SyncApi('https://sync.example', 'token', client: transport);
      if (status == 200 || status == 409) {
        expect(await api.put('h1', 100, 'cipher'), status == 200);
      } else {
        await expectLater(
          api.put('h1', 100, 'cipher'),
          throwsA(
            isA<SyncApiException>().having((e) => e.status, 'status', status),
          ),
        );
      }
    });
  }

  test('删除已经不存在的记录按成功处理', () async {
    final transport = _syncClient((request) async => http.Response('', 404));
    addTearDown(transport.close);
    await SyncApi(
      'https://sync.example',
      'token',
      client: transport,
    ).delete('missing');
  });

  test('显式重新加入同步才发送恢复删除记录标志', () async {
    final transport = _syncClient((request) async {
      expect((jsonDecode(request.body) as Map)['restoreDeleted'], isTrue);
      return http.Response('{}', 200);
    });
    addTearDown(transport.close);
    expect(
      await SyncApi(
        'https://sync.example',
        'token',
        client: transport,
      ).put('h1', 100, 'cipher', restoreDeleted: true),
      isTrue,
    );
  });

  test('下载返回损坏 JSON 时抛出格式错误', () async {
    final transport = _syncClient(
      (request) async => http.Response('not-json', 200),
    );
    addTearDown(transport.close);
    await expectLater(
      SyncApi('https://sync.example', 'token', client: transport).fetch(['h1']),
      throwsFormatException,
    );
  });

  test('网络超时向上传播，不伪装为空索引', () async {
    final transport = _syncClient(
      (request) async => throw TimeoutException('offline'),
    );
    addTearDown(transport.close);
    await expectLater(
      SyncApi('https://sync.example', 'token', client: transport).index(),
      throwsA(isA<TimeoutException>()),
    );
  });
  test('主机 UUID 作为单个路径段编码，不会改写请求路径', () async {
    final paths = <String>[];
    final transport = _syncClient((request) async {
      paths.add(request.url.path);
      return http.Response('{}', 200);
    });
    addTearDown(transport.close);
    final api = SyncApi('https://sync.example', 'token', client: transport);
    await api.put('a b/../c?#', 1, 'cipher');
    await api.delete('a b/../c?#');
    expect(paths, everyElement('/api/v1/items/a%20b%2F..%2Fc%3F%23'));
  });

  for (final (name, call) in <(String, Future<void> Function(SyncApi))>[
    ('连接检测', (api) => api.ping()),
    ('索引', (api) => api.index()),
    ('下载', (api) => api.fetch(['h1'])),
    ('删除', (api) => api.delete('h1')),
  ]) {
    test('$name 遇到 401/500 抛出带状态码的异常', () async {
      for (final status in [401, 500]) {
        final transport = MockClient(
          (request) async => http.Response('{"error":"x"}', status),
        );
        addTearDown(transport.close);
        await expectLater(
          call(SyncApi('https://sync.example', 'token', client: transport)),
          throwsA(
            isA<SyncApiException>().having((e) => e.status, 'status', status),
          ),
        );
      }
    });
  }
}
