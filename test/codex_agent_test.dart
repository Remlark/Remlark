import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:remlark/modules/ai/agent_config.dart';
import 'package:remlark/modules/ai/agent_interface.dart';
import 'package:remlark/modules/ai/agents/codex_agent.dart';
import 'package:remlark/modules/ai/codex/codex_account_service.dart';
import 'package:remlark/modules/ai/codex/codex_app_server.dart';

import 'helpers/fake_codex_server.dart';

AgentSettings _settings({String model = ''}) => AgentSettings(
  uuid: 'agent-1',
  name: 'Codex',
  kind: AgentKind.codex,
  model: model,
  createdAt: 0,
);

void main() {
  test('新线程：系统提示词作为 baseInstructions，流式输出、推理与用量', () async {
    final fake = FakeCodexServer();
    final server = CodexAppServer(launcher: (_) async => fake.connection, workspace: () async => '/tmp/rmk-codex');
    final agent = CodexAgent(_settings(model: 'gpt-b').copyWith(reasoningEffort: 'high'), server: server);
    final events = await agent.send(const AgentRequest(history: [], prompt: '查一下磁盘', systemPrompt: 'PROTOCOL')).toList();

    final text = events.whereType<AgentTextDelta>().map((e) => e.text).join();
    expect(text, '你好，世界');
    expect(events.whereType<AgentReasoningDelta>().single.text, '想一想');
    expect(events.whereType<AgentSessionId>().single.id, 'th-1');
    expect(events.whereType<AgentError>(), isEmpty);
    final usage = events.whereType<AgentUsage>().single;
    expect((usage.inputTokens, usage.outputTokens, usage.contextTokens, usage.estimated), (100, 20, 120, false));

    final start = fake.params('thread/start');
    expect(start['baseInstructions'], 'PROTOCOL');
    expect(start['sandbox'], 'read-only');
    expect(start['approvalPolicy'], 'never');
    expect(start['model'], 'gpt-b');
    expect(fake.params('turn/start')['effort'], 'high');
    expect(start['cwd'], '/tmp/rmk-codex');
    expect(fake.params('turn/start')['input'][0]['text'], '查一下磁盘');
    await server.shutdown();
  });

  test('同一进程中续问直接开始新一轮；进程重启后恢复线程', () async {
    final fake = FakeCodexServer();
    final server = CodexAppServer(launcher: (_) async => fake.connection, workspace: () async => '/tmp/rmk-codex');
    await CodexAgent(_settings(), server: server).send(const AgentRequest(history: [], prompt: '1')).toList();
    final again = await CodexAgent(
      _settings(),
      server: server,
    ).send(const AgentRequest(history: [], prompt: '2', externalSessionId: 'th-1')).toList();
    expect(again.whereType<AgentSessionId>(), isEmpty);
    expect(fake.methods.where((m) => m == 'thread/start').length, 1);
    expect(fake.methods, isNot(contains('thread/resume')));
    // 未选择推理强度时不传，使用模型默认
    expect(fake.params('turn/start').containsKey('effort'), isFalse);
    await server.shutdown();

    final restarted = FakeCodexServer(knownThreads: {'th-1'});
    final server2 = CodexAppServer(launcher: (_) async => restarted.connection, workspace: () async => '/tmp/rmk-codex');
    await CodexAgent(
      _settings(),
      server: server2,
    ).send(const AgentRequest(history: [], prompt: '3', externalSessionId: 'th-1')).toList();
    expect(restarted.methods, contains('thread/resume'));
    expect(restarted.methods, isNot(contains('thread/start')));
    expect(restarted.params('turn/start')['input'][0]['text'], '3');
    await server2.shutdown();
  });

  test('线程无法恢复时新建线程并附上之前的对话', () async {
    final fake = FakeCodexServer();
    final server = CodexAppServer(launcher: (_) async => fake.connection, workspace: () async => '/tmp/rmk-codex');
    final events = await CodexAgent(_settings(), server: server)
        .send(
          const AgentRequest(
            history: [AgentMessage('user', '旧问题'), AgentMessage('assistant', '旧回答')],
            prompt: '新问题',
            externalSessionId: 'gone',
          ),
        )
        .toList();
    expect(events.whereType<AgentSessionId>().single.id, 'th-1');
    final first = fake.params('turn/start')['input'][0]['text'] as String;
    expect(first, contains('User: 旧问题'));
    expect(first, contains('Assistant: 旧回答'));
    expect(first, endsWith('新问题'));
    await server.shutdown();
  });

  test('未登录时直接提示登录，不创建线程', () async {
    final fake = FakeCodexServer(loggedIn: false);
    final server = CodexAppServer(launcher: (_) async => fake.connection, workspace: () async => '/tmp/rmk-codex');
    final events = await CodexAgent(_settings(), server: server).send(const AgentRequest(history: [], prompt: 'hi')).toList();
    expect(events.whereType<AgentError>().single.message, contains('Codex'));
    expect(fake.methods, isNot(contains('thread/start')));
    await server.shutdown();
  });

  test('取消时中断当前轮次', () async {
    final fake = FakeCodexServer()..holdTurn = true;
    final server = CodexAppServer(launcher: (_) async => fake.connection, workspace: () async => '/tmp/rmk-codex');
    final agent = CodexAgent(_settings(), server: server);
    final events = <AgentEvent>[];
    final done = Completer<void>();
    agent.send(const AgentRequest(history: [], prompt: 'long')).listen(events.add, onDone: done.complete);
    while (!fake.methods.contains('turn/start')) {
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
    await Future<void>.delayed(const Duration(milliseconds: 20));
    agent.cancel();
    await done.future.timeout(const Duration(seconds: 5));
    expect(fake.methods, contains('turn/interrupt'));
    expect(events.whereType<AgentError>(), isEmpty);
    await server.shutdown();
  });

  test('账号与模型列表', () async {
    final fake = FakeCodexServer();
    final service = CodexAccountService(
      server: CodexAppServer(launcher: (_) async => fake.connection, workspace: () async => '/tmp/rmk-codex'),
    );
    final account = await service.readAccount('agent-1');
    expect((account?.email, account?.planLabel), ('a@b.c', 'Plus'));
    final fake2 = FakeCodexServer();
    final models = await CodexAccountService(
      server: CodexAppServer(launcher: (_) async => fake2.connection, workspace: () async => '/tmp/rmk-codex'),
    ).listModels('agent-1');
    expect(models.map((m) => m.id), ['gpt-a', 'gpt-b']);
    expect(models.first.isDefault, isTrue);
    expect(models.first.efforts, ['low', 'medium', 'high']);
    expect(models.first.defaultEffort, 'medium');
  });

  test('同一 CODEX_HOME 的进程启动排队进行，握手完成后才启动下一个', () async {
    var starting = 0;
    var maxStarting = 0;
    final server = CodexAppServer(
      launcher: (_) async {
        // 正在启动（尚未完成握手）的进程数
        maxStarting = ++starting > maxStarting ? starting : maxStarting;
        await Future<void>.delayed(const Duration(milliseconds: 20));
        return (FakeCodexServer()..onInitialized = () => starting--).connection;
      },
      workspace: () async => '/tmp/rmk-codex',
    );
    final conns = await Future.wait([for (var i = 0; i < 3; i++) server.open('home')]);
    expect(conns.length, 3);
    expect(maxStarting, 1);
    for (final c in conns) {
      await c.close();
    }
  });
}
