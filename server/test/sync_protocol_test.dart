import 'dart:convert';

import 'package:remlark_sync_server/remlark_sync_server.dart';
import 'package:remlark_sync_server/src/api/sync_protocol.dart';
import 'package:shelf/shelf.dart';
import 'package:test/test.dart';

/// 验证所有接口在读取数据库或解析数据之前强制校验同步协议。
void main() {
  late SyncDatabase db;
  late Handler handler;
  setUp(() {
    db = SyncDatabase.memory();
    handler = SyncApi(SyncRepository(db), ['tok']).handler;
  });
  tearDown(() => db.close());

  /// 构造真实路由请求，未传版本表示历史 1.0 客户端。
  Future<Response> send(
    String method,
    String path, {
    String? version,
    String? body,
  }) async => handler(
    Request(
      method,
      Uri.parse('http://unit.test/api/v1/$path'),
      headers: {
        'Authorization': 'Bearer tok',
        if (version != null) SyncProtocol.header: version,
      },
      body: body,
    ),
  );

  for (final version in [null, '1.0']) {
    test('兼容版本 $version 可写入，握手及数据响应明确声明 1.0', () async {
      final ping = await send('GET', 'ping', version: version);
      expect(ping.statusCode, 200);
      final metadata = jsonDecode(await ping.readAsString()) as Map;
      expect(metadata['protocolVersion'], '1.0');
      expect(metadata['supportedProtocolVersions'], ['1.0']);
      final put = await send(
        'PUT',
        'items/h1',
        version: version,
        body: '{"updatedAt":100,"payload":"cipher"}',
      );
      expect(put.statusCode, 200);
      expect(put.headers[SyncProtocol.header.toLowerCase()], '1.0');
      final index = await send('GET', 'items', version: version);
      expect(
        (jsonDecode(await index.readAsString()) as Map)['items'],
        hasLength(1),
      );
    });
  }

  for (final version in ['2.0', '1.1', '1', '', 'garbage']) {
    test('拒绝未知或畸形协议 $version，所有接口返回 426 且不修改数据', () async {
      await send(
        'PUT',
        'items/h1',
        body: '{"updatedAt":100,"payload":"original"}',
      );
      for (final (method, path) in [
        ('GET', 'ping'),
        ('GET', 'items'),
        ('POST', 'items/batch-get'),
        ('PUT', 'items/h1'),
        ('DELETE', 'items/h1'),
      ]) {
        final response = await send(
          method,
          path,
          version: version,
          body: 'invalid-json',
        );
        expect(response.statusCode, 426, reason: '$method $path');
        final error = jsonDecode(await response.readAsString()) as Map;
        expect(error['error'], 'unsupported_sync_protocol');
        expect(error['supportedProtocolVersions'], ['1.0']);
      }
      final index = await send('GET', 'items');
      expect(
        ((jsonDecode(await index.readAsString()) as Map)['items'] as List)
            .single,
        {'uuid': 'h1', 'updatedAt': 100, 'deleted': false},
      );
    });
  }

  test('认证错误仍返回 401', () async {
    final response = await handler(
      Request(
        'GET',
        Uri.parse('http://unit.test/api/v1/ping'),
        headers: {SyncProtocol.header: '2.0'},
      ),
    );
    expect(response.statusCode, 401);
  });
}
