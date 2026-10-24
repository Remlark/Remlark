import 'dart:convert';

import 'package:http/http.dart' as http;

/// 服务器上一条记录的索引信息
class RemoteItemInfo {
  const RemoteItemInfo(this.uuid, this.updatedAt, this.deleted);

  final String uuid;
  final int updatedAt;
  final bool deleted;
}

/// 与密文同时读取的服务端版本，避免索引和下载之间更新导致版本错配。
class RemoteItemPayload extends RemoteItemInfo {
  const RemoteItemPayload(
    super.uuid,
    super.updatedAt,
    super.deleted,
    this.payload,
  );

  final String? payload;
}

/// 同步服务器 HTTP 接口
class SyncApi {
  SyncApi(this.baseUrl, this.token, {this.client});

  final String baseUrl;
  final String token;
  final http.Client? client;

  static const _timeout = Duration(seconds: 20);

  Uri _uri(String path) {
    var b = baseUrl.trim();
    if (b.endsWith('/')) b = b.substring(0, b.length - 1);
    return Uri.parse('$b/api/v1$path');
  }

  Map<String, String> get _headers => {
    'Authorization': 'Bearer $token',
    'Content-Type': 'application/json',
  };

  /// 统一发送请求；测试可注入内存 HTTP 客户端，默认请求自行释放连接资源。
  Future<http.Response> _request(
    String method,
    String path, {
    Object? body,
  }) async {
    final request = http.Request(method, _uri(path))..headers.addAll(_headers);
    if (body != null) request.body = jsonEncode(body);
    final response = client?.send(request) ?? request.send();
    return response.then(http.Response.fromStream).timeout(_timeout);
  }

  void _check(http.Response r) {
    if (r.statusCode >= 300) {
      throw SyncApiException(r.statusCode, r.body);
    }
  }

  /// 连通性检测
  Future<void> ping() async {
    final r = await _request('GET', '/ping');
    _check(r);
  }

  /// 获取全部条目索引（uuid、更新时间、是否删除）
  Future<Map<String, RemoteItemInfo>> index() async {
    final r = await _request('GET', '/items');
    _check(r);
    final list = (jsonDecode(r.body) as Map)['items'] as List;
    return {
      for (final e in list.cast<Map>())
        e['uuid'] as String: RemoteItemInfo(
          e['uuid'] as String,
          (e['updatedAt'] as num).toInt(),
          e['deleted'] == true,
        ),
    };
  }

  /// 批量获取条目载荷（加密）
  Future<Map<String, RemoteItemPayload>> fetch(List<String> uuids) async {
    if (uuids.isEmpty) return {};
    final ids = uuids.toSet().toList();
    final items = <String, RemoteItemPayload>{};
    // 服务端单批最多 1000 台，去重后分批避免大主机库同步被拒绝。
    for (var offset = 0; offset < ids.length; offset += 1000) {
      final end = (offset + 1000).clamp(0, ids.length);
      final r = await _request(
        'POST',
        '/items/batch-get',
        body: {'uuids': ids.sublist(offset, end)},
      );
      _check(r);
      final list = (jsonDecode(r.body) as Map)['items'] as List;
      for (final e in list.cast<Map>()) {
        items[e['uuid'] as String] = RemoteItemPayload(
          e['uuid'] as String,
          (e['updatedAt'] as num).toInt(),
          e['deleted'] == true,
          e['payload'] as String?,
        );
      }
    }
    return items;
  }

  /// 上传条目；服务器上的版本更新时返回 false
  Future<bool> put(
    String uuid,
    int updatedAt,
    String payload, {
    bool restoreDeleted = false,
  }) async {
    final r = await _request(
      'PUT',
      '/items/${Uri.encodeComponent(uuid)}',
      body: {
        'updatedAt': updatedAt,
        'payload': payload,
        'restoreDeleted': restoreDeleted,
      },
    );
    if (r.statusCode == 409) return false;
    _check(r);
    return true;
  }

  /// 从服务器删除（留下删除标记，其他客户端据此停止同步该主机）
  Future<void> delete(String uuid) async {
    final r = await _request('DELETE', '/items/${Uri.encodeComponent(uuid)}');
    if (r.statusCode == 404) return;
    _check(r);
  }
}

/// 同步接口异常
class SyncApiException implements Exception {
  const SyncApiException(this.status, this.body);

  final int status;
  final String body;

  @override
  String toString() => 'HTTP $status $body';
}
