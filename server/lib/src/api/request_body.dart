import 'dart:convert';

/// 请求体格式错误，由接口层转换为 HTTP 400。
class BadRequest implements Exception {
  const BadRequest(this.message);

  final String message;

  @override
  String toString() => 'BadRequest: $message';
}

/// 解析 JSON 对象请求体；非 JSON 或非对象均视为格式错误。
Map<String, dynamic> parseJsonObject(String body) {
  final Object? decoded;
  try {
    decoded = jsonDecode(body);
  } on FormatException {
    throw const BadRequest('invalid json');
  }
  if (decoded is! Map<String, dynamic>) {
    throw const BadRequest('body must be an object');
  }
  return decoded;
}

/// 批量读取请求：uuids 必须是字符串数组。
List<String> parseBatchGet(Map<String, dynamic> body) {
  final uuids = body['uuids'];
  if (uuids is! List || uuids.any((e) => e is! String)) {
    throw const BadRequest('uuids must be a string list');
  }
  return uuids.cast<String>();
}

/// 上传请求的已校验字段。
typedef PutBody = ({int updatedAt, String payload, bool restoreDeleted});

/// 上传请求：版本必须是整数，载荷必须是非空字符串，恢复标志可省略。
PutBody parsePut(Map<String, dynamic> body) {
  final updatedAt = body['updatedAt'];
  final payload = body['payload'];
  final restore = body['restoreDeleted'] ?? false;
  if (updatedAt is! int) throw const BadRequest('updatedAt must be an int');
  // 空载荷与删除标记的存储形式相同，接受后会出现无法解密的“有效”记录。
  if (payload is! String || payload.isEmpty) {
    throw const BadRequest('payload must be a non-empty string');
  }
  if (restore is! bool) throw const BadRequest('restoreDeleted must be a bool');
  return (updatedAt: updatedAt, payload: payload, restoreDeleted: restore);
}
