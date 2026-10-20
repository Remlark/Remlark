import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:remlark/data/database.dart';
import 'package:remlark/modules/ai/agent_config.dart';
import 'package:remlark/modules/ai/agent_interface.dart';
import 'package:remlark/modules/ai/agents/deepseek_harness_agent.dart';
import 'package:remlark/modules/ai/chat_controller.dart';
import 'package:remlark/modules/ai/chat_repository.dart';
import 'package:remlark/modules/ai/runtime/json_rpc_connection.dart';
import 'package:remlark/modules/ai/dsh/dsh_acp_service.dart';
import 'package:remlark/modules/ai/terminal_agent/command_permission.dart';
import 'package:remlark/modules/ai/terminal_agent/read_only_commands.dart';
import 'package:remlark/modules/ai/terminal_agent/terminal_agent_protocol.dart';
import 'package:remlark/modules/ai/terminal_agent/terminal_driver.dart';
import 'package:remlark/modules/ai/terminal_agent/terminal_step_runner.dart';
import 'package:remlark/modules/ai/token_repository.dart';
import 'package:remlark/utils/ansi_utils.dart';
import 'package:remlark/utils/version_utils.dart';

/// 内存中的假 dsh ACP 进程：记录收到的请求，按 ACP 协议回复
class FakeAcpAgent {
  FakeAcpAgent({this.knownSessions = const {}, this.replies, this.lateText = false});

  /// 模拟 dsh 偶发的乱序：先返回提问结束，再送达回答文本
  final bool lateText;

  /// 可以 session/resume 的会话
  final Set<String> knownSessions;

  /// 按顺序作为每次提问的完整回复（为 null 时使用固定的流式回复）
  final List<String>? replies;
  int _replyIndex = 0;

  /// 每次提问的文本
  List<String> get prompts => [
    for (final r in requests)
      if (r['method'] == 'session/prompt') r['params']['prompt'][0]['text'] as String,
  ];

  final _toClient = StreamController<List<int>>();
  final _fromClient = StreamController<List<int>>();
  final requests = <Map<String, dynamic>>[];
  final permissionReplies = <Map<String, dynamic>>[];
  int _sessions = 0;

  /// 提示词完成前等待（测试取消）
  Completer<void>? holdPrompt;
  Map<String, dynamic>? _pendingPrompt;

  late final JsonRpcConnection connection = () {
    _fromClient.stream.transform(utf8.decoder).transform(const LineSplitter()).listen(_onLine);
    return JsonRpcConnection(_toClient.stream, _fromClient.sink, onClose: () async => _toClient.close());
  }();

  List<String> get methods => requests.map((r) => r['method'] as String).toList();

  void _send(Map<String, dynamic> m) => _toClient.add(utf8.encode('${jsonEncode({'jsonrpc': '2.0', ...m})}\n'));

  void _update(String sid, Map<String, dynamic> u) => _send({
    'method': 'session/update',
    'params': {'sessionId': sid, 'update': u},
  });

  static const _configOptions = [
    {
      'id': 'model',
      'category': 'model',
      'currentValue': '["deepseek-official","deepseek-v4-flash"]',
      'options': [
        {
          'group': 'deepseek-official',
          'options': [
            {'value': '["deepseek-official","deepseek-v4-flash"]', 'name': 'deepseek-v4-flash'},
            {'value': '["deepseek-official","deepseek-v4-pro"]', 'name': 'deepseek-v4-pro'},
          ],
        },
      ],
    },
    {
      'id': 'reasoning_effort',
      'category': 'thought_level',
      'currentValue': 'high',
      'options': [
        {'value': 'off', 'name': 'Off'},
        {'value': 'low', 'name': 'Low'},
        {'value': 'high', 'name': 'High'},
        {'value': 'max', 'name': 'Max'},
      ],
    },
  ];

  Future<void> _onLine(String line) async {
    final m = jsonDecode(line) as Map<String, dynamic>;
    if (m['method'] == null) {
      permissionReplies.add(m);
      return;
    }
    requests.add(m);
    final id = m['id'];
    final params = m['params'] as Map<String, dynamic>;
    switch (m['method']) {
      case 'initialize':
        _send({
          'id': id,
          'result': {'protocolVersion': 1},
        });
      case 'session/new':
        _send({
          'id': id,
          'result': {'sessionId': 's-${++_sessions}', 'configOptions': _configOptions},
        });
      case 'session/resume':
        if (knownSessions.contains(params['sessionId'])) {
          _send({
            'id': id,
            'result': {'configOptions': _configOptions},
          });
        } else {
          _send({
            'id': id,
            'error': {'code': -32602, 'message': 'unknown session'},
          });
        }
      case 'session/close':
        _send({'id': id, 'result': <String, dynamic>{}});
      case 'session/set_config_option':
        _send({'id': id, 'result': <String, dynamic>{}});
      case 'session/cancel':
        final p = _pendingPrompt;
        if (p != null) {
          _pendingPrompt = null;
          _send({
            'id': p['id'],
            'result': {'stopReason': 'cancelled'},
          });
        }
      case 'session/prompt':
        final sid = params['sessionId'] as String;
        final script = replies;
        if (script != null) {
          final reply = _replyIndex < script.length ? script[_replyIndex++] : '{"action":"answer","message":"end"}';
          void chunk() => _update(sid, {
            'sessionUpdate': 'agent_message_chunk',
            'content': {'type': 'text', 'text': reply},
          });
          if (lateText) {
            _send({
              'id': id,
              'result': {'stopReason': 'end_turn'},
            });
            await Future<void>.delayed(const Duration(milliseconds: 80));
            chunk();
            return;
          }
          chunk();
          final hold = holdPrompt;
          if (hold != null) {
            _pendingPrompt = m;
            await hold.future;
            return;
          }
          _send({
            'id': id,
            'result': {'stopReason': 'end_turn'},
          });
          return;
        }
        // 工具调用前请求权限，客户端应拒绝
        _send({
          'id': 900,
          'method': 'session/request_permission',
          'params': {
            'sessionId': sid,
            'options': [
              {'optionId': 'ok', 'kind': 'allow_once', 'name': 'Allow'},
              {'optionId': 'no', 'kind': 'reject_once', 'name': 'Reject'},
            ],
          },
        });
        _update(sid, {
          'sessionUpdate': 'agent_thought_chunk',
          'content': {'type': 'text', 'text': '想一想'},
        });
        _update(sid, {'sessionUpdate': 'tool_call', 'toolCallId': 't1', 'title': 'bash'});
        _update(sid, {
          'sessionUpdate': 'agent_message_chunk',
          'content': {'type': 'text', 'text': '你好，'},
        });
        _update(sid, {
          'sessionUpdate': 'agent_message_chunk',
          'content': {'type': 'text', 'text': '执行：\n```bash\nuptime\n```'},
        });
        _update(sid, {'sessionUpdate': 'usage_update', 'used': 4321, 'size': 128000});
        final hold = holdPrompt;
        if (hold != null) {
          _pendingPrompt = m;
          await hold.future;
          return;
        }
        _send({
          'id': id,
          'result': {'stopReason': 'end_turn'},
        });
    }
  }
}

/// 测试用的 dsh Agent 配置
const settings = AgentSettings(
  uuid: 'a1',
  name: 'DSH',
  kind: AgentKind.deepseekCli,
  apiKey: 'sk-test',
  model: 'deepseek-v4-pro',
  createdAt: 0,
);

/// 收集一轮事件
Future<List<AgentEvent>> collect(Stream<AgentEvent> s) => s.toList();

void main() {
  test('版本号比较：数字逐段、预发布低于正式版、预发布段按数值', () {
    expect(VersionUtils.compare('0.2.1', '0.2.1-rc.2'), greaterThan(0));
    expect(VersionUtils.compare('0.2.1-rc.10', '0.2.1-rc.2'), greaterThan(0));
    expect(VersionUtils.compare('0.2.1-alpha.5', '0.2.1-rc.1'), lessThan(0));
    expect(VersionUtils.compare('v24.11.1', '24.11.1'), 0);
    expect(VersionUtils.compare('0.10.0', '0.9.9'), greaterThan(0));
    expect(VersionUtils.parseOutput('dsh 0.2.1-rc.2\n'), '0.2.1-rc.2');
    expect(VersionUtils.normalize('dsh-v0.2.1'), '0.2.1');
  });

  test('DeepSeek Harness：ACP 新建会话、切换模型、流式输出、拒绝权限、会话 id 与 token 统计', () async {
    final fake = FakeAcpAgent();
    String? launchedKey;
    DshAcpService.shared = DshAcpService(
      launcher: (key) async {
        launchedKey = key;
        return fake.connection;
      },
      workspace: () async => '/tmp/rmk-ws',
    );

    final db = AppDatabase(NativeDatabase.memory());
    final chats = ChatRepository(db);
    final tokens = TokenRepository(db);
    final c = ChatController(chats: chats, tokens: tokens, hostName: 'web');
    await c.send(settings, '服务器负载如何？', context: 'load average: 0.1');

    expect(launchedKey, 'sk-test');
    expect(fake.methods, ['initialize', 'session/new', 'session/set_config_option', 'session/prompt']);
    expect(fake.requests[1]['params']['cwd'], '/tmp/rmk-ws');
    expect(fake.requests[2]['params']['value'], '["deepseek-official","deepseek-v4-pro"]');
    // 新会话的第一条消息带系统提示词与终端上下文
    final firstPrompt = fake.requests[3]['params']['prompt'][0]['text'] as String;
    expect(firstPrompt, contains('SSH terminal client'));
    expect(firstPrompt, contains('load average: 0.1'));
    // 权限请求选择了拒绝
    expect(fake.permissionReplies.single['result']['outcome']['optionId'], 'no');

    final reply = c.messages.last;
    expect(reply.role, 'assistant');
    expect(reply.content, '你好，执行：\n```bash\nuptime\n```');
    expect(reply.reasoning, contains('想一想'));
    expect(reply.reasoning, contains('bash'));
    expect(c.stats.contextTokens, 4321);
    expect(c.stats.estimated, isTrue);
    expect(c.session!.externalSessionId, 's-1');

    // 第二轮：同一进程中直接续问，不再新建或恢复会话，也不重复系统提示词
    await c.send(settings, '继续');
    expect(fake.methods.skip(4), ['session/prompt']);
    expect(fake.requests.last['params']['sessionId'], 's-1');
    expect(fake.requests.last['params']['prompt'][0]['text'], '继续');

    final sessions = await chats.listSessions();
    final msgs = await chats.messages(sessions.single.id);
    expect(msgs.map((m) => m.role), ['user', 'assistant', 'user', 'assistant']);
    final now = DateTime.now();
    expect((await tokens.summary(now, now)).requests, 2);
    expect((await tokens.byAgent(now, now)).single.key, 'DSH');
  });

  test('DeepSeek Harness：进程重启后恢复会话；恢复失败时新建会话并附上之前的对话', () async {
    // 已持久化的会话可以恢复
    final fake = FakeAcpAgent(knownSessions: {'s-old'});
    final service = DshAcpService(launcher: (_) async => fake.connection, workspace: () async => '/tmp/rmk-ws');
    final agent = DeepSeekHarnessAgent(settings, service: service);
    final events = await collect(
      agent.send(
        const AgentRequest(
          history: [AgentMessage('user', '上一问'), AgentMessage('assistant', '上一答')],
          prompt: '再问',
          externalSessionId: 's-old',
          systemPrompt: 'SYS',
        ),
      ),
    );
    expect(fake.methods, ['initialize', 'session/resume', 'session/set_config_option', 'session/prompt']);
    expect(fake.requests.last['params']['prompt'][0]['text'], '再问');
    expect(events.whereType<AgentSessionId>(), isEmpty);
    expect(events.whereType<AgentError>(), isEmpty);

    // 会话已丢失：新建会话，第一条消息带系统提示词与之前的对话
    final lost = FakeAcpAgent();
    final service2 = DshAcpService(launcher: (_) async => lost.connection, workspace: () async => '/tmp/rmk-ws');
    final events2 = await collect(
      DeepSeekHarnessAgent(settings, service: service2).send(
        const AgentRequest(
          history: [AgentMessage('user', '上一问'), AgentMessage('assistant', '上一答')],
          prompt: '再问',
          externalSessionId: 's-gone',
          systemPrompt: 'SYS',
        ),
      ),
    );
    expect(lost.methods, ['initialize', 'session/resume', 'session/new', 'session/set_config_option', 'session/prompt']);
    final text = lost.requests.last['params']['prompt'][0]['text'] as String;
    expect(text, startsWith('SYS'));
    expect(text, contains('User: 上一问'));
    expect(text, contains('Assistant: 上一答'));
    expect(text, endsWith('再问'));
    expect(events2.whereType<AgentSessionId>().single.id, 's-1');
  });

  test('DeepSeek Harness：取消时发送 session/cancel，本轮正常结束', () async {
    final fake = FakeAcpAgent()..holdPrompt = Completer<void>();
    final service = DshAcpService(launcher: (_) async => fake.connection, workspace: () async => '/tmp/rmk-ws');
    final agent = DeepSeekHarnessAgent(settings, service: service);
    final events = <AgentEvent>[];
    final done = Completer<void>();
    agent.send(const AgentRequest(history: [], prompt: '长任务')).listen(events.add, onDone: done.complete);
    // 等到收到第一段输出再取消
    while (!events.any((e) => e is AgentTextDelta)) {
      await Future<void>.delayed(const Duration(milliseconds: 5));
    }
    agent.cancel();
    await done.future.timeout(const Duration(seconds: 5));
    expect(fake.methods, contains('session/cancel'));
    expect(events.whereType<AgentError>(), isEmpty);
    expect(events.last, isA<AgentUsage>());
  });

  test('DeepSeek Harness：进程退出后下次提问重新启动', () async {
    var launches = 0;
    final fakes = <FakeAcpAgent>[];
    final service = DshAcpService(
      launcher: (_) async {
        launches++;
        final f = FakeAcpAgent();
        fakes.add(f);
        return f.connection;
      },
      workspace: () async => '/tmp/rmk-ws',
    );
    final agent = DeepSeekHarnessAgent(settings, service: service);
    await collect(agent.send(const AgentRequest(history: [], prompt: '一')));
    await fakes.single.connection.close();
    await collect(agent.send(const AgentRequest(history: [], prompt: '二')));
    expect(launches, 2);
  });

  terminalAgentTests();
}

/// 假的终端：记录输入的命令；[onType] 模拟 shell 的输出
class FakeTerminal implements TerminalDriver {
  final outCtl = StreamController<String>.broadcast();
  final inputCtl = StreamController<String>.broadcast();
  final typed = <(String, bool)>[];
  void Function(String command, bool submit)? onType;
  bool online = true;

  @override
  String get hostLabel => 'web-01';

  @override
  bool get connected => online;

  @override
  Stream<String> get output => outCtl.stream;

  @override
  Stream<String> get userInput => inputCtl.stream;

  @override
  void type(String command, {required bool submit}) {
    typed.add((command, submit));
    onType?.call(command, submit);
  }

  @override
  String screenText({int lines = 30}) => 'root@web-01:~# ';

  /// 模拟 shell 输出
  void emit(String s) => outCtl.add(s);
}

String run(String cmd, [String msg = '']) => jsonEncode({'action': 'run', 'command': cmd, 'message': msg});
String wait(int s) => jsonEncode({'action': 'wait', 'seconds': s, 'message': ''});
String answer(String msg) => '```json\n${jsonEncode({'action': 'answer', 'message': msg})}\n```';

void terminalAgentTests() {
  setUp(() {
    DeepSeekHarnessAgent.settleQuiet = const Duration(milliseconds: 30);
    DeepSeekHarnessAgent.settleEmptyMax = const Duration(milliseconds: 400);
    // 缩短等待，测试更快
    TerminalStepRunner.runIdle = const Duration(milliseconds: 150);
    TerminalStepRunner.runMax = const Duration(seconds: 2);
    TerminalStepRunner.waitIdle = const Duration(milliseconds: 150);
    TerminalStepRunner.minCollect = const Duration(milliseconds: 50);
  });

  /// 创建绑定假终端的聊天
  (ChatController, FakeAcpAgent, FakeTerminal, AppDatabase) setup(List<String> replies, {String host = 'web-01'}) {
    final fake = FakeAcpAgent(replies: replies);
    DshAcpService.shared = DshAcpService(launcher: (_) async => fake.connection, workspace: () async => '/tmp/rmk-ws');
    final db = AppDatabase(NativeDatabase.memory());
    final term = FakeTerminal();
    final c = ChatController(chats: ChatRepository(db), tokens: TokenRepository(db), hostName: host, terminal: term);
    return (c, fake, term, db);
  }

  test('协议解析：json 代码块、裸 JSON、普通文字作为回答、wait 秒数限制', () {
    final a = TerminalAgentProtocol.parse('好的\n```json\n{"action":"run","command":"df -h","message":"看硬盘"}\n```');
    expect((a.type, a.command, a.message), (TerminalActionType.run, 'df -h', '看硬盘'));
    expect(TerminalAgentProtocol.parse('{"action":"wait","seconds":9999}').seconds, TerminalAgentProtocol.maxWait);
    expect(TerminalAgentProtocol.parse('{"action":"wait","seconds":0}').seconds, TerminalAgentProtocol.minWait);
    final plain = TerminalAgentProtocol.parse('你好！有什么可以帮你？');
    expect((plain.type, plain.message), (TerminalActionType.answer, '你好！有什么可以帮你？'));
    expect(TerminalAgentProtocol.parse('{"action":"run","command":""}').type, TerminalActionType.answer);
    expect(TerminalAgentProtocol.parse(answer('**完成**')).message, '**完成**');
  });

  test('终端输出转纯文本：去掉颜色与控制序列，进度条只保留最后状态，过长保留末尾', () {
    expect(AnsiUtils.toPlainText('\x1b[32mroot@web\x1b[0m:~# ls\r\n\x1b]0;title\x07a  b\r\n'), 'root@web:~# ls\na  b\n');
    expect(AnsiUtils.toPlainText('Progress 10%\rProgress 55%\rProgress 100%\n'), 'Progress 100%\n');
    expect(AnsiUtils.toPlainText('abc\b\bX'), 'aX');
    expect(AnsiUtils.tail('x' * 50, 10), endsWith('x' * 10));
    expect(AnsiUtils.tail('x' * 50, 10), contains('40 earlier characters omitted'));
  });

  test('终端操作：全部自动执行时直接回车，把输出交给 AI，最后在聊天中回答', () async {
    final (c, fake, term, db) = setup([run('df -h /', '查看硬盘'), answer('硬盘 100G，已用 40%')]);
    c.permission = CommandPermission.autoAll;
    term.onType = (cmd, submit) => Future<void>.delayed(const Duration(milliseconds: 30), () {
      term.emit('\x1b[1m$cmd\x1b[0m\r\n/dev/vda1  100G  40G  60G  40% /\r\nroot@web-01:~# ');
    });
    await c.send(settings, '这台服务器硬盘多大');

    expect(term.typed, [('df -h /', true)]);
    // 整个任务在同一个 dsh 会话中进行（上下文由 dsh 保存），只新建一次会话
    expect(fake.methods.where((m) => m == 'session/new'), hasLength(1));
    final sids = {for (final r in fake.requests) if (r['method'] == 'session/prompt') r['params']['sessionId']};
    expect(sids, {'s-1'});
    // 第一次提问：协议说明（新会话）+ 问题 + 当前屏幕
    expect(fake.prompts.first, contains('"action":"run"'));
    expect(fake.prompts.first, contains('remote server "web-01"'));
    expect(fake.prompts.first, contains('[Current terminal screen]'));
    // 第二次提问：终端输出（已去掉控制序列）
    expect(fake.prompts[1], contains('/dev/vda1  100G'));
    expect(fake.prompts[1], isNot(contains('\x1b')));
    // 聊天中依次显示：问题、本步说明与命令、终端输出、最终回答
    expect(c.messages.map((m) => m.role), ['user', 'assistant', 'terminal', 'assistant']);
    expect(c.messages[1].content, contains('查看硬盘'));
    expect(c.messages[1].content, contains('```bash\ndf -h /\n```'));
    expect(c.messages.last.content, '硬盘 100G，已用 40%');
    expect(c.busy, isFalse);
    // 记录持久化（包含终端输出）
    final saved = await c.chats.messages(c.session!.id);
    expect(saved.map((m) => m.role), ['user', 'assistant', 'terminal', 'assistant']);
    c.dispose();
    await db.close();
  });

  test('终端操作：逐条确认时只填入不回车，用户在终端按回车后继续；按 Ctrl+C 则告知 AI 未执行', () async {
    final (c, fake, term, db) = setup([run('apt install -y nginx'), run('rm -rf /tmp/x'), answer('好的')]);
    c.permission = CommandPermission.ask;
    var n = 0;
    term.onType = (cmd, submit) {
      expect(submit, isFalse);
      Future<void>.delayed(const Duration(milliseconds: 50), () {
        expect(c.waitingForEnter, isTrue);
        if (n++ == 0) {
          term.inputCtl.add('\r');
          term.emit('$cmd\r\nSetting up nginx ...\r\nroot@web-01:~# ');
        } else {
          term.inputCtl.add('\x03');
        }
      });
    };
    await c.send(settings, '装个 nginx');
    expect(term.typed.map((t) => t.$2), [false, false]);
    expect(fake.prompts[1], contains('Setting up nginx'));
    expect(fake.prompts[2], TerminalAgentProtocol.notExecuted);
    expect(c.waitingForEnter, isFalse);
    c.dispose();
    await db.close();
  });

  test('终端操作：只读自动执行时查看命令直接回车，修改命令等待回车', () async {
    final (c, _, term, db) = setup([run('systemctl status nginx --no-pager'), run('systemctl restart nginx'), answer('ok')]);
    c.permission = CommandPermission.autoReadOnly;
    term.onType = (cmd, submit) => Future<void>.delayed(const Duration(milliseconds: 30), () {
      if (!submit) term.inputCtl.add('\r');
      term.emit('$cmd\r\nroot@web-01:~# ');
    });
    await c.send(settings, '看下 nginx 然后重启');
    expect(term.typed, [('systemctl status nginx --no-pager', true), ('systemctl restart nginx', false)]);
    c.dispose();
    await db.close();
  });

  test('终端操作：长命令由 AI 判断未结束并 wait，期间（含 AI 思考时）的新输出都会交给 AI', () async {
    final (c, fake, term, db) = setup([run('apt upgrade -y'), wait(5), answer('升级完成')]);
    c.permission = CommandPermission.autoAll;
    // wait 期间输出间隔 300ms，停顿判定需长于它
    TerminalStepRunner.waitIdle = const Duration(milliseconds: 500);
    term.onType = (cmd, submit) async {
      term.emit('$cmd\r\nReading package lists...\r\n');
      // 汇报之后继续输出（AI 思考期间与 wait 期间）
      await Future<void>.delayed(const Duration(milliseconds: 400));
      term.emit('Unpacking libc6 ...\r\n');
      await Future<void>.delayed(const Duration(milliseconds: 300));
      term.emit('Processing triggers ...\r\nroot@web-01:~# ');
    };
    await c.send(settings, '升级系统');
    expect(fake.prompts[1], contains('Reading package lists'));
    expect(fake.prompts[1], isNot(contains('Processing triggers')));
    expect(fake.prompts[2], contains('since the last report'));
    expect(fake.prompts[2], contains('Unpacking libc6'));
    expect(fake.prompts[2], contains('Processing triggers'));
    expect(c.messages.last.content, '升级完成');
    c.dispose();
    await db.close();
  });

  test('终端操作：等待回车时点停止，任务结束，不再提问', () async {
    final (c, fake, term, db) = setup([run('reboot'), answer('不应出现')]);
    term.onType = (_, _) => Future<void>.delayed(const Duration(milliseconds: 50), c.stop);
    await c.send(settings, '重启');
    expect(fake.prompts, hasLength(1));
    expect(c.busy, isFalse);
    expect(c.messages.last.content, isNot('不应出现'));
    c.dispose();
    await db.close();
  });

  test('终端操作：普通问题直接在聊天中回答，不操作终端；只给建议模式下照常流式对话', () async {
    final (c, fake, term, db) = setup(['你好！有什么可以帮你？', '用 `df -h` 查看']);
    await c.send(settings, '你好');
    expect(term.typed, isEmpty);
    expect(c.messages.map((m) => m.role), ['user', 'assistant']);
    expect(c.messages.last.content, '你好！有什么可以帮你？');

    // 切到只给建议：续聊时告知 AI 不再操作终端
    c.permission = CommandPermission.suggestOnly;
    await c.send(settings, '怎么看硬盘');
    expect(fake.prompts.last, startsWith('[The user turned off terminal control.'));
    // 只给建议时也附上终端当前屏幕
    expect(fake.prompts.last, contains('[Current terminal screen]'));
    expect(fake.prompts.last, contains('root@web-01:~#'));
    expect(c.messages.last.content, '用 `df -h` 查看');
    expect(term.typed, isEmpty);
    // 聊天有消息后绑定开始时的 Agent；新对话解除绑定
    expect(c.boundAgentUuid, settings.uuid);
    c.newChat();
    expect(c.boundAgentUuid, isNull);
    c.dispose();
    await db.close();
  });

  test('OpenAI 兼容 API：每一步都带上整个对话（AI 原始 JSON 回复与终端输出），新对话后清空', () async {
    final replies = [run('df -h /'), answer('100G'), answer('ok')];
    final bodies = <List<dynamic>>[];
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((req) async {
      final body = jsonDecode(await utf8.decodeStream(req)) as Map<String, dynamic>;
      bodies.add(body['messages'] as List);
      final text = replies[bodies.length - 1];
      req.response.headers.contentType = ContentType('text', 'event-stream', charset: 'utf-8');
      req.response.write('data: ${jsonEncode({
        'choices': [
          {
            'delta': {'content': text},
          },
        ],
      })}\n\ndata: [DONE]\n\n');
      await req.response.close();
    });
    final db = AppDatabase(NativeDatabase.memory());
    final term = FakeTerminal();
    term.onType = (cmd, submit) => Future<void>.delayed(const Duration(milliseconds: 30), () => term.emit('$cmd\r\n/dev/vda1 100G\r\n# '));
    final c = ChatController(chats: ChatRepository(db), tokens: TokenRepository(db), hostName: 'web-01', terminal: term)
      ..permission = CommandPermission.autoAll;
    final api = AgentSettings(uuid: 'o1', name: 'API', kind: AgentKind.openaiApi, endpoint: 'http://127.0.0.1:${server.port}', model: 'test-model', createdAt: 0);

    await c.send(api, '硬盘多大');
    // 第 2 步：系统提示 + 用户问题 + AI 原始 JSON + 终端输出（作为本次提问）
    final step2 = bodies[1].map((m) => '${m['role']}: ${m['content']}').toList();
    expect(step2.first, startsWith('system: '));
    expect(step2[1], startsWith('user: 硬盘多大'));
    expect(step2[2], 'assistant: ${run('df -h /')}');
    expect(step2.last, contains('/dev/vda1 100G'));

    // 同一对话再问：带上整个上一轮任务
    await c.send(api, '谢谢');
    final step3 = bodies[2].map((m) => '${m['role']}').toList();
    expect(step3, ['system', 'user', 'assistant', 'user', 'assistant', 'user']);
    expect(bodies[2][3]['content'], contains('/dev/vda1 100G'));
    expect(bodies[2][4]['content'], answer('100G'));

    // 新对话：只有系统提示与新问题
    c.newChat();
    replies.add(answer('hi'));
    await c.send(api, '你好');
    expect(bodies.last.map((m) => m['role']), ['system', 'user']);
    c.dispose();
    await db.close();
    await server.close(force: true);
  });

  test('dsh 先返回提问结束、后送达回答时，仍能收到回答', () async {
    final fake = FakeAcpAgent(replies: [answer('迟到的回答')], lateText: true);
    final service = DshAcpService(launcher: (_) async => fake.connection, workspace: () async => '/tmp/rmk-ws');
    final events = await DeepSeekHarnessAgent(settings, service: service).send(const AgentRequest(history: [], prompt: 'q')).toList();
    expect(events.whereType<AgentTextDelta>().map((e) => e.text).join(), answer('迟到的回答'));
  });

  test('终端操作：没有收到回复时请 AI 重新回复一次；仍没有则在聊天中提示，不会悄悄结束', () async {
    var (c, fake, _, db) = setup(['', answer('重试后的回答')]);
    await c.send(settings, '内存前 10');
    expect(fake.prompts.last, TerminalAgentProtocol.noReply);
    expect(c.messages.last.content, '重试后的回答');
    c.dispose();
    await db.close();

    (c, fake, _, db) = setup(['', '']);
    await c.send(settings, '内存前 10');
    expect(c.messages.last.role, 'error');
    expect(c.messages.last.content, contains('没有给出回复'));
    expect(c.busy, isFalse);
    c.dispose();
    await db.close();
  });

  test('只读命令判断：白名单、子命令、修改类参数、重定向与命令替换', () {
    for (final c in [
      'df -h',
      'ls -la /var/log',
      'cat /etc/os-release | grep -i name',
      'free -m && uptime',
      'systemctl status nginx --no-pager',
      'journalctl -u nginx -n 50 --no-pager',
      'docker ps -a',
      'docker compose logs --tail 20',
      'ip addr show',
      'ps aux | sort -k3 -nr | head',
      'find /var/log -name "*.log" -size +10M',
      'du -sh /var/* 2>/dev/null | sort -h',
      'timeout 5 ping -c 3 8.8.8.8',
      'kubectl get pods -A',
      'top -bn1 | head -20',
      'crontab -l',
      'nginx -t',
    ]) {
      expect(ReadOnlyCommands.isReadOnly(c), isTrue, reason: c);
    }
    for (final c in [
      'rm -rf /tmp/x',
      'systemctl restart nginx',
      'echo hi > /etc/motd',
      'cat a >> b',
      'sudo df -h',
      'find / -name x -delete',
      r'find . -exec rm {} \;',
      "sed -i 's/a/b/' f",
      'ls; rm -rf /',
      'df -h && reboot',
      r'echo $(rm -rf /)',
      'echo `id`',
      'sleep 100 &',
      'ip route add default via 1.1.1.1',
      'docker rm -f web',
      'docker network rm n',
      'docker stats',
      'kubectl delete pod x',
      'crontab -r',
      'mount /dev/sdb1 /mnt',
      'apt install nginx',
      'top',
      'curl -X POST http://x',
      '',
    ]) {
      expect(ReadOnlyCommands.isReadOnly(c), isFalse, reason: c);
    }
  });

  test('聊天：在其他服务器的终端里载入历史记录不续用原 dsh 会话，也不改写原记录', () async {
    final fake = FakeAcpAgent(knownSessions: {'s-1'}, replies: [answer('a'), answer('b'), answer('c')]);
    DshAcpService.shared = DshAcpService(launcher: (_) async => fake.connection, workspace: () async => '/tmp/rmk-ws');
    final db = AppDatabase(NativeDatabase.memory());
    final chats = ChatRepository(db);
    final tokens = TokenRepository(db);
    final a = ChatController(chats: chats, tokens: tokens, hostName: 'web-01', terminal: FakeTerminal());
    await a.send(settings, '硬盘多大');
    final record = a.session!;
    expect(record.externalSessionId, 's-1');

    final b = ChatController(chats: chats, tokens: tokens, hostName: 'db-01', terminal: FakeTerminal());
    await b.loadSession(record);
    final before = fake.requests.length;
    await b.send(settings, '那这台呢');
    final newMethods = fake.requests.skip(before).map((r) => r['method']).toList();
    expect(newMethods, isNot(contains('session/resume')));
    expect(newMethods, contains('session/new'));
    // 新会话的协议说明指向 db-01
    expect(fake.prompts.last, contains('remote server "db-01"'));
    expect((await chats.getSession(record.id))!.externalSessionId, 's-1');

    final before2 = fake.requests.length;
    await b.send(settings, '继续');
    expect(fake.requests.skip(before2).map((r) => r['method']), ['session/prompt']);
    a.dispose();
    b.dispose();
    await db.close();
  });

  test('DeepSeek Harness：可选模型与推理强度来自会话配置项，并按 API Key 缓存', () async {
    final fake = FakeAcpAgent();
    final service = DshAcpService(launcher: (_) async => fake.connection, workspace: () async => '/tmp/rmk-ws');
    final opts = await service.options('sk-test');
    expect(opts.models.map((m) => m.id), ['deepseek-v4-flash', 'deepseek-v4-pro']);
    expect(opts.defaultModel?.id, 'deepseek-v4-flash');
    expect(opts.models.first.efforts, ['off', 'low', 'high', 'max']);
    expect(opts.models.first.defaultEffort, 'high');
    await service.options('sk-test');
    expect(fake.methods.where((m) => m == 'session/new').length, 1);
    await service.shutdown();
  });

  test('DeepSeek Harness：每轮按配置切换推理强度，改回默认时恢复会话默认值', () async {
    final fake = FakeAcpAgent();
    final service = DshAcpService(launcher: (_) async => fake.connection, workspace: () async => '/tmp/rmk-ws');
    const base = AgentSettings(uuid: 'a1', name: 'DSH', kind: AgentKind.deepseekCli, createdAt: 0);
    List<Map<String, dynamic>> sets() => [
      for (final r in fake.requests)
        if (r['method'] == 'session/set_config_option') (r['params'] as Map).cast<String, dynamic>(),
    ];

    final events = await collect(
      DeepSeekHarnessAgent(
        base.copyWith(reasoningEffort: 'max'),
        service: service,
      ).send(const AgentRequest(history: [], prompt: '1')),
    );
    final sid = events.whereType<AgentSessionId>().single.id;
    expect(sets().map((p) => (p['configId'], p['value'])), [('reasoning_effort', 'max')]);

    // 同一会话中改为默认模型与默认推理强度：推理强度切回 high，模型本来就是默认不需要切换
    await collect(
      DeepSeekHarnessAgent(base, service: service).send(AgentRequest(history: const [], prompt: '2', externalSessionId: sid)),
    );
    expect(sets().map((p) => (p['configId'], p['value'])), [('reasoning_effort', 'max'), ('reasoning_effort', 'high')]);

    // 中途切换模型
    await collect(
      DeepSeekHarnessAgent(
        base.copyWith(model: 'deepseek-v4-pro'),
        service: service,
      ).send(AgentRequest(history: const [], prompt: '3', externalSessionId: sid)),
    );
    expect(sets().last['value'], '["deepseek-official","deepseek-v4-pro"]');
    await service.shutdown();
  });
}
