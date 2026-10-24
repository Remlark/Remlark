import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:remlark_sync_server/remlark_sync_server.dart';
import 'package:shelf/shelf_io.dart' as io;
import 'package:test/test.dart';

void main() {
  late HttpServer server;
  late SyncDatabase db;
  late String base;
  final h = {'Authorization': 'Bearer t1', 'Content-Type': 'application/json'};

  setUp(() async {
    db = SyncDatabase.memory();
    final api = SyncApi(SyncRepository(db), ['t1', 't2']);
    server = await io.serve(api.handler, '127.0.0.1', 0);
    base = 'http://127.0.0.1:${server.port}/api/v1';
  });
  tearDown(() async {
    await server.close(force: true);
    await db.close();
  });

  test('未授权返回 401', () async {
    final r = await http.get(Uri.parse('$base/items'));
    expect(r.statusCode, 401);
  });

  test('删除后普通上传返回冲突，显式恢复标志可以恢复主机', () async {
    final uri = Uri.parse('$base/items/deleted-host');
    await http.put(
      uri,
      headers: h,
      body: jsonEncode({'updatedAt': 100, 'payload': 'cipher'}),
    );
    await http.delete(uri, headers: h);
    final ordinary = await http.put(
      uri,
      headers: h,
      body: jsonEncode({'updatedAt': 200, 'payload': 'stale'}),
    );
    expect(ordinary.statusCode, 409);
    final explicit = await http.put(
      uri,
      headers: h,
      body: jsonEncode({
        'updatedAt': 200,
        'payload': 'restored',
        'restoreDeleted': true,
      }),
    );
    expect(explicit.statusCode, 200);
  });

  test('写入、索引、冲突、批量读取、删除标记、空间隔离', () async {
    var r = await http.put(
      Uri.parse('$base/items/a'),
      headers: h,
      body: jsonEncode({'updatedAt': 100, 'payload': 'X'}),
    );
    expect(r.statusCode, 200);
    // 旧版本写入被拒绝
    r = await http.put(
      Uri.parse('$base/items/a'),
      headers: h,
      body: jsonEncode({'updatedAt': 50, 'payload': 'old'}),
    );
    expect(r.statusCode, 409);
    r = await http.put(
      Uri.parse('$base/items/a'),
      headers: h,
      body: jsonEncode({'updatedAt': 200, 'payload': 'Y'}),
    );
    expect(r.statusCode, 200);
    r = await http.get(Uri.parse('$base/items'), headers: h);
    final items = (jsonDecode(r.body) as Map)['items'] as List;
    expect(items.single['updatedAt'], 200);
    r = await http.post(
      Uri.parse('$base/items/batch-get'),
      headers: h,
      body: jsonEncode({
        'uuids': ['a'],
      }),
    );
    expect(
      ((jsonDecode(r.body) as Map)['items'] as List).single['payload'],
      'Y',
    );
    // 其他令牌看不到
    r = await http.get(
      Uri.parse('$base/items'),
      headers: {'Authorization': 'Bearer t2'},
    );
    expect((jsonDecode(r.body) as Map)['items'], isEmpty);
    // 删除留下标记
    r = await http.delete(Uri.parse('$base/items/a'), headers: h);
    expect(r.statusCode, 200);
    r = await http.get(Uri.parse('$base/items'), headers: h);
    expect(
      ((jsonDecode(r.body) as Map)['items'] as List).single['deleted'],
      true,
    );
  });
  test('所有接口都要求有效令牌，空令牌和未知令牌均返回 401', () async {
    for (final auth in ['', 'Bearer ', 'Bearer unknown', 't1']) {
      for (final (method, path) in [
        ('GET', 'ping'),
        ('GET', 'items'),
        ('POST', 'items/batch-get'),
        ('PUT', 'items/a'),
        ('DELETE', 'items/a'),
      ]) {
        final request = http.Request(method, Uri.parse('$base/$path'));
        if (auth.isNotEmpty) request.headers['Authorization'] = auth;
        final r = await http.Response.fromStream(await request.send());
        expect(r.statusCode, 401, reason: '$method $path with "$auth"');
      }
    }
  });

  for (final (name, body) in [
    ('非 JSON', 'not-json'),
    ('JSON 数组', '[]'),
    ('缺少 uuids', '{}'),
    ('uuids 不是数组', '{"uuids":"a"}'),
    ('uuids 含非字符串', '{"uuids":["a",1]}'),
  ]) {
    test('批量读取请求体$name时返回 400 而不是 500', () async {
      final r = await http.post(
        Uri.parse('$base/items/batch-get'),
        headers: h,
        body: body,
      );
      expect(r.statusCode, 400);
    });
  }

  for (final (name, body) in [
    ('非 JSON', 'not-json'),
    ('缺少 updatedAt', '{"payload":"x"}'),
    ('updatedAt 不是数字', '{"updatedAt":"1","payload":"x"}'),
    ('updatedAt 为小数', '{"updatedAt":1.5,"payload":"x"}'),
    ('缺少 payload', '{"updatedAt":1}'),
    ('payload 不是字符串', '{"updatedAt":1,"payload":1}'),
    ('payload 为空', '{"updatedAt":1,"payload":""}'),
    ('restoreDeleted 不是布尔', '{"updatedAt":1,"payload":"x","restoreDeleted":"yes"}'),
  ]) {
    test('上传请求体$name时返回 400 且不写入记录', () async {
      final r = await http.put(
        Uri.parse('$base/items/bad'),
        headers: h,
        body: body,
      );
      expect(r.statusCode, 400);
      final index = await http.get(Uri.parse('$base/items'), headers: h);
      expect((jsonDecode(index.body) as Map)['items'], isEmpty);
    });
  }

  test('批量读取超过 1000 条返回 400，恰好 1000 条正常返回', () async {
    final tooMany = await http.post(
      Uri.parse('$base/items/batch-get'),
      headers: h,
      body: jsonEncode({'uuids': [for (var i = 0; i < 1001; i++) 'h$i']}),
    );
    expect(tooMany.statusCode, 400);
    final limit = await http.post(
      Uri.parse('$base/items/batch-get'),
      headers: h,
      body: jsonEncode({'uuids': [for (var i = 0; i < 1000; i++) 'h$i']}),
    );
    expect(limit.statusCode, 200);
    expect((jsonDecode(limit.body) as Map)['items'], isEmpty);
  });

  test('载荷超过 1MB 返回 413 且不覆盖已有版本', () async {
    final uri = Uri.parse('$base/items/big');
    await http.put(
      uri,
      headers: h,
      body: jsonEncode({'updatedAt': 100, 'payload': 'small'}),
    );
    final r = await http.put(
      uri,
      headers: h,
      body: jsonEncode({'updatedAt': 200, 'payload': 'x' * (1024 * 1024 + 1)}),
    );
    expect(r.statusCode, 413);
    final index = await http.get(Uri.parse('$base/items'), headers: h);
    expect(((jsonDecode(index.body) as Map)['items'] as List).single, {
      'uuid': 'big',
      'updatedAt': 100,
      'deleted': false,
    });
  });

  test('删除不存在的主机返回 404，重复删除保持删除标记', () async {
    var r = await http.delete(Uri.parse('$base/items/missing'), headers: h);
    expect(r.statusCode, 404);
    final uri = Uri.parse('$base/items/a');
    await http.put(
      uri,
      headers: h,
      body: jsonEncode({'updatedAt': 100, 'payload': 'X'}),
    );
    expect((await http.delete(uri, headers: h)).statusCode, 200);
    expect((await http.delete(uri, headers: h)).statusCode, 200);
    r = await http.post(
      Uri.parse('$base/items/batch-get'),
      headers: h,
      body: jsonEncode({'uuids': ['a']}),
    );
    final item = ((jsonDecode(r.body) as Map)['items'] as List).single as Map;
    expect(item['deleted'], isTrue);
    expect(item.containsKey('payload'), isFalse);
  });

  test('含特殊字符的主机 UUID 编码后可写入、读取和删除', () async {
    const uuid = 'imported host/#1?';
    final path = Uri.encodeComponent(uuid);
    final r = await http.put(
      Uri.parse('$base/items/$path'),
      headers: h,
      body: jsonEncode({'updatedAt': 100, 'payload': 'X'}),
    );
    expect(r.statusCode, 200);
    final index = await http.get(Uri.parse('$base/items'), headers: h);
    expect(
      ((jsonDecode(index.body) as Map)['items'] as List).single['uuid'],
      uuid,
    );
    final deleted = await http.delete(
      Uri.parse('$base/items/$path'),
      headers: h,
    );
    expect(deleted.statusCode, 200);
  });
}
