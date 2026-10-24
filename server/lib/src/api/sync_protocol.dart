import 'dart:convert';

import 'package:shelf/shelf.dart';

/// 服务端同步协议策略；新增版本必须同时提供该版本的路由和语义实现。
abstract final class SyncProtocol {
  static const version = '1.0';
  static const supportedVersions = ['1.0'];
  static const legacyVersion = '1.0';
  static const header = 'x-remlark-sync-protocol';

  /// 旧客户端未声明版本时仅按历史 1.0 处理。
  static bool supports(String? requested) =>
      supportedVersions.contains(requested ?? legacyVersion);

  /// 每个接口读写前检查协议，不支持时返回 426，所有响应均声明处理协议。
  static Middleware get middleware =>
      (inner) => (request) async {
        final requested = request.headers[header.toLowerCase()];
        if (!supports(requested)) {
          return Response(
            426,
            headers: {'Content-Type': 'application/json', header: version},
            body: jsonEncode({
              'error': 'unsupported_sync_protocol',
              'protocolVersion': version,
              'supportedProtocolVersions': supportedVersions,
            }),
          );
        }
        final response = await inner(request);
        return response.change(headers: {header: requested ?? legacyVersion});
      };
}
