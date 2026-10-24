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
}
