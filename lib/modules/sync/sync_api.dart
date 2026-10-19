import 'dart:convert';

import 'package:http/http.dart' as http;

/// 服务器上一条记录的索引信息
class RemoteItemInfo {
  const RemoteItemInfo(this.uuid, this.updatedAt, this.deleted);

  final String uuid;
  final int updatedAt;
  final bool deleted;
}

/// 同步服务器 HTTP 接口
class SyncApi {
  SyncApi(this.baseUrl, this.token);

  final String baseUrl;
  final String token;

  static const _timeout = Duration(seconds: 20);

  Uri _uri(String path) {
    var b = baseUrl.trim();
    if (b.endsWith('/')) b = b.substring(0, b.length - 1);
    return Uri.parse('$b/api/v1$path');
  }

  Map<String, String> get _headers => {'Authorization': 'Bearer $token', 'Content-Type': 'application/json'};

  void _check(http.Response r) {
    if (r.statusCode >= 300) {
      throw SyncApiException(r.statusCode, r.body);
    }
  }

  /// 连通性检测
  Future<void> ping() async {
    final r = await http.get(_uri('/ping'), headers: _headers).timeout(_timeout);
    _check(r);
  }

  /// 获取全部条目索引（uuid、更新时间、是否删除）
  Future<Map<String, RemoteItemInfo>> index() async {
    final r = await http.get(_uri('/items'), headers: _headers).timeout(_timeout);
    _check(r);
    final list = (jsonDecode(r.body) as Map)['items'] as List;
    return {
      for (final e in list.cast<Map>())
        e['uuid'] as String: RemoteItemInfo(e['uuid'] as String, (e['updatedAt'] as num).toInt(), e['deleted'] == true),
    };
  }

  /// 批量获取条目载荷（加密）
  Future<Map<String, String>> fetch(List<String> uuids) async {
    if (uuids.isEmpty) return {};
    final r = await http
        .post(_uri('/items/batch-get'), headers: _headers, body: jsonEncode({'uuids': uuids}))
        .timeout(_timeout);
    _check(r);
    final list = (jsonDecode(r.body) as Map)['items'] as List;
    return {
      for (final e in list.cast<Map>())
        if (e['payload'] is String) e['uuid'] as String: e['payload'] as String,
    };
  }

  /// 上传条目；服务器上的版本更新时返回 false
  Future<bool> put(String uuid, int updatedAt, String payload) async {
    final r = await http
        .put(_uri('/items/$uuid'), headers: _headers, body: jsonEncode({'updatedAt': updatedAt, 'payload': payload}))
        .timeout(_timeout);
    if (r.statusCode == 409) return false;
    _check(r);
    return true;
  }

  /// 从服务器删除（留下删除标记，其他客户端据此停止同步该主机）
  Future<void> delete(String uuid) async {
    final r = await http.delete(_uri('/items/$uuid'), headers: _headers).timeout(_timeout);
    if (r.statusCode == 404) return;
    _check(r);
  }
}

/// 同步接口异常
class SyncApiException implements Exception {
  SyncApiException(this.status, this.body);

  final int status;
  final String body;

  @override
  String toString() => 'HTTP $status $body';
}
