import 'dart:async';
import 'dart:convert';

import 'package:remlark/modules/ai/runtime/json_rpc_connection.dart';

/// 内存中的假 codex app-server：记录请求，按协议回复线程、轮次与流式通知
class FakeCodexServer {
  FakeCodexServer({this.loggedIn = true, this.knownThreads = const {}});

  bool loggedIn;

  /// 可以 thread/resume 的线程
  final Set<String> knownThreads;

  final _toClient = StreamController<List<int>>();
  final _fromClient = StreamController<List<int>>();
  final requests = <Map<String, dynamic>>[];
  int _threads = 0;

  /// 为 true 时 turn/start 后不自动完成（测试取消）
  bool holdTurn = false;

  /// 收到 initialized 通知（握手完成）时调用
  void Function()? onInitialized;

  late final JsonRpcConnection connection = () {
    _fromClient.stream.transform(utf8.decoder).transform(const LineSplitter()).listen(_onLine);
    return JsonRpcConnection(_toClient.stream, _fromClient.sink, onClose: () async => _toClient.close());
  }();

  List<String> get methods => requests.map((r) => r['method'] as String).toList();

  /// 某个方法最近一次请求的参数
  Map<String, dynamic> params(String method) =>
      requests.lastWhere((r) => r['method'] == method)['params'] as Map<String, dynamic>;

  void _send(Map<String, dynamic> m) => _toClient.add(utf8.encode('${jsonEncode(m)}\n'));

  void _notify(String method, Map<String, dynamic> params) => _send({'method': method, 'params': params});

  void _onLine(String line) {
    final m = jsonDecode(line) as Map<String, dynamic>;
    if (m['method'] == null) return;
    requests.add(m);
    final id = m['id'];
    if (m['method'] == 'initialized') onInitialized?.call();
    if (id == null) return;
    final p = (m['params'] as Map?)?.cast<String, dynamic>() ?? const {};
    switch (m['method']) {
      case 'initialize':
        _send({'id': id, 'result': {'userAgent': 'fake'}});
      case 'account/read':
        _send({
          'id': id,
          'result': {'account': loggedIn ? {'type': 'chatgpt', 'email': 'a@b.c', 'planType': 'plus'} : null},
        });
      case 'model/list':
        _send({
          'id': id,
          'result': {
            'data': [
              {
                'model': 'gpt-a',
                'displayName': 'GPT-A',
                'isDefault': true,
                'defaultReasoningEffort': 'medium',
                'supportedReasoningEfforts': [
                  {'reasoningEffort': 'low'},
                  {'reasoningEffort': 'medium'},
                  {'reasoningEffort': 'high'},
                ],
              },
              {'model': 'gpt-b', 'displayName': 'GPT-B'},
            ],
          },
        });
      case 'thread/start':
        _send({
          'id': id,
          'result': {
            'thread': {'id': 'th-${++_threads}'},
          },
        });
      case 'thread/resume':
        final tid = p['threadId'];
        if (knownThreads.contains(tid)) {
          _send({
            'id': id,
            'result': {
              'thread': {'id': tid},
            },
          });
        } else {
          _send({
            'id': id,
            'error': {'code': -32600, 'message': 'no rollout found'},
          });
        }
      case 'turn/start':
        final tid = p['threadId'] as String;
        _send({
          'id': id,
          'result': {
            'turn': {'id': 'turn-1', 'status': 'inProgress'},
          },
        });
        if (holdTurn) return;
        _notify('item/reasoning/summaryTextDelta', {'threadId': tid, 'itemId': 'r1', 'delta': '想一想'});
        _notify('item/agentMessage/delta', {'threadId': tid, 'itemId': 'm1', 'delta': '你好'});
        _notify('item/agentMessage/delta', {'threadId': tid, 'itemId': 'm1', 'delta': '，世界'});
        // 已流式输出过的消息，完成时不再重复
        _notify('item/completed', {
          'threadId': tid,
          'item': {'type': 'agentMessage', 'id': 'm1', 'text': '你好，世界'},
        });
        // 其他线程的通知不应混入
        _notify('item/agentMessage/delta', {'threadId': 'other', 'itemId': 'x', 'delta': '串台'});
        _notify('thread/tokenUsage/updated', {
          'threadId': tid,
          'turnId': 'turn-1',
          'tokenUsage': {
            'last': {'inputTokens': 100, 'outputTokens': 20, 'totalTokens': 120},
          },
        });
        _notify('turn/completed', {
          'threadId': tid,
          'turn': {'id': 'turn-1', 'status': 'completed'},
        });
      case 'turn/interrupt':
        _send({'id': id, 'result': {}});
        _notify('turn/completed', {
          'threadId': p['threadId'],
          'turn': {'id': 'turn-1', 'status': 'interrupted'},
        });
      default:
        _send({'id': id, 'result': {}});
    }
  }
}
