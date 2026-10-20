import 'dart:async';
import 'dart:convert';

/// JSON-RPC 对端发来的通知
class JsonRpcNotification {
  const JsonRpcNotification(this.method, this.params);

  final String method;
  final Map<String, dynamic> params;
}

/// JSON-RPC 调用失败：对端返回 JSON-RPC 错误，或连接已断开（[code] 为 null）
class JsonRpcException implements Exception {
  JsonRpcException(this.message, {this.code});

  final String message;
  final int? code;

  @override
  String toString() => message;
}

/// 基于标准输入输出的 JSON-RPC 2.0 连接（每行一条 JSON 消息），dsh 的 ACP 与 Codex 的 app-server 共用。
///
/// 请求按 id 匹配响应；没有 id 的消息作为通知广播；对端发来的请求交给 [onRequest]，
/// 未设置处理器时回复“方法不存在”。
class JsonRpcConnection {
  /// 基于已有的输入输出流创建（测试时可传入内存中的假 Agent）
  JsonRpcConnection(Stream<List<int>> stdout, this._stdin, {Stream<List<int>>? stderr, Future<void> Function()? onClose})
    // 命名参数不能用私有的初始化形参，因此显式赋值
    // ignore: prefer_initializing_formals
    : _onClose = onClose {
    stdout
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen(_onLine, onError: (Object e) => _fail('$e'), onDone: () => _fail(null));
    stderr?.transform(utf8.decoder).listen(_recordStderr, onError: (_) {});
  }

  final StreamSink<List<int>> _stdin;
  final Future<void> Function()? _onClose;
  final _pending = <int, Completer<Map<String, dynamic>>>{};
  final _notifications = StreamController<JsonRpcNotification>.broadcast();
  final _done = Completer<void>();
  final _stderrTail = StringBuffer();
  int _seq = 0;
  bool _closed = false;

  /// 连接断开的原因（进程退出时为标准错误输出的末尾几行）
  String? closeReason;

  /// 对端发来的请求（如权限确认）；返回值作为 result 回复，抛出异常则回复错误
  Future<Map<String, dynamic>> Function(String method, Map<String, dynamic> params)? onRequest;

  /// 通知流（需在发出请求之前订阅，否则可能错过）
  Stream<JsonRpcNotification> get notifications => _notifications.stream;

  /// 连接结束（进程退出或主动关闭）时完成
  Future<void> get done => _done.future;

  /// 连接是否已断开
  bool get closed => _closed;

  /// 发送请求并等待结果；[timeout] 为 null 时不限时（提示词可能运行很久）
  Future<Map<String, dynamic>> call(String method, Map<String, dynamic> params, {Duration? timeout}) {
    if (_closed) return Future.error(JsonRpcException(closeReason ?? 'closed'));
    final id = ++_seq;
    final completer = Completer<Map<String, dynamic>>();
    _pending[id] = completer;
    _send({'jsonrpc': '2.0', 'id': id, 'method': method, 'params': params});
    if (timeout == null) return completer.future;
    return completer.future.timeout(
      timeout,
      onTimeout: () {
        _pending.remove(id);
        throw JsonRpcException('timeout: $method');
      },
    );
  }

  /// 发送通知（不等待响应）
  void notify(String method, Map<String, dynamic> params) =>
      _send({'jsonrpc': '2.0', 'method': method, 'params': params});

  /// 关闭连接并结束对端进程
  Future<void> close() async {
    if (_closed) return;
    _fail(null);
    try {
      await _stdin.close();
    } catch (_) {}
    await _onClose?.call();
  }

  /// 写入一条消息
  void _send(Map<String, dynamic> message) {
    if (_closed) return;
    try {
      _stdin.add(utf8.encode('${jsonEncode(message)}\n'));
    } catch (_) {
      // 进程已退出时写入失败，由 stdout 的 onDone 统一报告
    }
  }

  /// 处理一行输出：响应、通知或对端发来的请求
  void _onLine(String line) {
    if (_closed || line.trim().isEmpty) return;
    final Map<String, dynamic> message;
    try {
      message = jsonDecode(line) as Map<String, dynamic>;
    } catch (_) {
      return; // stdout 只应包含协议帧，忽略意外的非 JSON 输出
    }
    final id = message['id'];
    final method = message['method'];
    final params = message['params'] is Map<String, dynamic> ? message['params'] as Map<String, dynamic> : const <String, dynamic>{};
    if (method is String) {
      if (id != null) {
        unawaited(_handleRequest(id, method, params));
      } else {
        _notifications.add(JsonRpcNotification(method, params));
      }
      return;
    }
    if (id is! int) return;
    final completer = _pending.remove(id);
    if (completer == null) return;
    final error = message['error'];
    if (error != null) {
      final text = error is Map ? '${error['message'] ?? error}' : '$error';
      completer.completeError(JsonRpcException(text, code: error is Map ? (error['code'] as num?)?.toInt() : null));
    } else {
      final result = message['result'];
      completer.complete(result is Map<String, dynamic> ? result : const {});
    }
  }

  /// 回复对端请求
  Future<void> _handleRequest(Object id, String method, Map<String, dynamic> params) async {
    Map<String, dynamic> response;
    try {
      final handler = onRequest;
      if (handler == null) throw JsonRpcException('unsupported: $method', code: -32601);
      response = {'jsonrpc': '2.0', 'id': id, 'result': await handler(method, params)};
    } catch (e) {
      response = {
        'jsonrpc': '2.0',
        'id': id,
        'error': {'code': e is JsonRpcException && e.code != null ? e.code : -32603, 'message': '$e'},
      };
    }
    _send(response);
  }

  /// 记录标准错误输出的末尾部分
  void _recordStderr(String text) {
    _stderrTail.write(text);
    if (_stderrTail.length > 8000) {
      final kept = _stderrTail.toString().substring(_stderrTail.length - 4000);
      _stderrTail
        ..clear()
        ..write(kept);
    }
  }

  /// 标准错误输出的最后几行
  String _stderrLines() {
    final lines = _stderrTail.toString().trim().split('\n').where((l) => l.trim().isNotEmpty).toList();
    final tail = lines.skip(lines.length > 4 ? lines.length - 4 : 0).join('\n');
    return tail.length > 600 ? tail.substring(tail.length - 600) : tail;
  }

  /// 连接结束：所有未完成的请求失败，通知流关闭
  void _fail(String? error) {
    if (_closed) return;
    _closed = true;
    final stderr = _stderrLines();
    closeReason = [?error, if (stderr.isNotEmpty) stderr].join('\n');
    if (closeReason!.isEmpty) closeReason = null;
    for (final c in _pending.values) {
      c.completeError(JsonRpcException(closeReason ?? 'closed'));
    }
    _pending.clear();
    _notifications.close();
    if (!_done.isCompleted) _done.complete();
  }
}
