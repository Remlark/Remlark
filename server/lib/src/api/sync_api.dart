import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';

import '../db/sync_repository.dart';
import 'request_body.dart';
import 'sync_protocol.dart';

/// 同步 HTTP 接口（/api/v1）。
/// 认证：`Authorization: Bearer <token>`，令牌决定数据空间，不同令牌数据互相隔离。
class SyncApi {
  SyncApi(this._repo, Iterable<String> tokens)
    : _spaces = {for (final t in tokens) t: spaceOf(t)};

  final SyncRepository _repo;
  final Map<String, String> _spaces;

  /// 令牌对应的数据空间 id
  static String spaceOf(String token) =>
      sha256.convert(utf8.encode(token)).toString().substring(0, 32);

  static const _json = {'Content-Type': 'application/json'};

  Response _ok(Object body) => Response.ok(jsonEncode(body), headers: _json);

  /// 认证中间件：校验令牌并把数据空间放入请求上下文
  Middleware get _auth =>
      (inner) => (req) {
        final h = req.headers['authorization'] ?? '';
        final token = h.startsWith('Bearer ') ? h.substring(7).trim() : '';
        final space = _spaces[token];
        if (space == null) {
          return Response(
            401,
            body: '{"error":"unauthorized"}',
            headers: _json,
          );
        }
        return inner(req.change(context: {'space': space}));
      };

  String _space(Request r) => r.context['space']! as String;

  /// 请求体格式错误统一返回 400，避免畸形请求被记为服务端 500。
  Middleware get _badRequest =>
      (inner) => (req) async {
        try {
          return await inner(req);
        } on BadRequest catch (e) {
          return Response(
            400,
            body: jsonEncode({'error': e.message}),
            headers: _json,
          );
        }
      };

  /// 路由参数保持 URL 编码，按路径段解码后才是客户端的主机 UUID。
  static String _uuid(String raw) {
    try {
      return Uri.decodeComponent(raw);
    } on ArgumentError {
      throw const BadRequest('invalid uuid');
    }
  }

  /// 构造处理器
  Handler get handler {
    final router = Router()
      ..get(
        '/api/v1/ping',
        (Request r) => _ok({
          'ok': true,
          'time': DateTime.now().millisecondsSinceEpoch,
          'protocolVersion':
              r.headers[SyncProtocol.header.toLowerCase()] ??
              SyncProtocol.legacyVersion,
          'supportedProtocolVersions': SyncProtocol.supportedVersions,
        }),
      )
      ..get(
        '/api/v1/items',
        (Request r) async => _ok({'items': await _repo.index(_space(r))}),
      )
      ..post('/api/v1/items/batch-get', (Request r) async {
        final uuids = parseBatchGet(parseJsonObject(await r.readAsString()));
        if (uuids.length > 1000) {
          return Response(400, body: '{"error":"too many"}', headers: _json);
        }
        final items = await _repo.fetch(_space(r), uuids);
        return _ok({
          'items': [
            for (final i in items)
              {
                'uuid': i.uuid,
                'updatedAt': i.updatedAt,
                'deleted': i.deleted,
                if (!i.deleted) 'payload': i.payload,
              },
          ],
        });
      })
      ..put('/api/v1/items/<uuid>', (Request r, String uuid) async {
        final body = parsePut(parseJsonObject(await r.readAsString()));
        if (body.payload.length > 1024 * 1024) {
          return Response(413, body: '{"error":"too large"}', headers: _json);
        }
        final res = await _repo.put(
          _space(r),
          _uuid(uuid),
          body.updatedAt,
          body.payload,
          restoreDeleted: body.restoreDeleted,
        );
        if (res == PutResult.conflict) {
          return Response(409, body: '{"error":"conflict"}', headers: _json);
        }
        return _ok({'ok': true});
      })
      ..delete('/api/v1/items/<uuid>', (Request r, String uuid) async {
        final found = await _repo.delete(_space(r), _uuid(uuid));
        return found
            ? _ok({'ok': true})
            : Response.notFound('{"error":"not found"}', headers: _json);
      });
    return const Pipeline()
        .addMiddleware(_auth)
        .addMiddleware(SyncProtocol.middleware)
        .addMiddleware(_badRequest)
        .addHandler(router.call);
  }
}
