import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:remlark/data/database.dart';
import 'package:remlark/modules/ai/agent_config.dart';
import 'package:remlark/modules/ai/chat_controller.dart';
import 'package:remlark/modules/ai/chat_repository.dart';
import 'package:remlark/modules/ai/token_repository.dart';

void main() {
  test('DeepSeek Harness CLI：NDJSON 流式输出、会话 id、token 统计与记录持久化', () async {
    if (Platform.isWindows) return;
    final dir = Directory.systemTemp.createTempSync('rmk_dsh');
    final script = File('${dir.path}/dsh')
      ..writeAsStringSync(r'''#!/bin/sh
prompt=$(cat)
echo "$@" > "$(dirname "$0")/args.txt"
echo '{"type":"session","session_id":"s-123"}'
sleep 0.2
echo '{"type":"text_delta","delta":"你好，"}'
echo '{"type":"text_delta","delta":"执行：\n```bash\nuptime\n```"}'
echo '{"type":"result","result":"ignored","usage":{"input_tokens":120,"output_tokens":30}}'
''');
    await Process.run('chmod', ['+x', script.path]);

    final db = AppDatabase(NativeDatabase.memory());
    final chats = ChatRepository(db);
    final tokens = TokenRepository(db);
    final c = ChatController(chats: chats, tokens: tokens, hostName: 'web');
    final agent = AgentSettings(
      uuid: 'a1',
      name: 'DSH',
      kind: AgentKind.deepseekCli,
      command: script.path,
      model: 'deepseek-v4',
      createdAt: 0,
    );
    await c.send(agent, '服务器负载如何？', context: 'load average: 0.1');
    final reply = c.messages.last;
    expect(reply.role, 'assistant');
    expect(reply.content, contains('uptime'));
    expect(c.stats.inputTokens, 120);
    expect(c.stats.outputTokens, 30);
    expect(c.stats.contextTokens, 150);
    expect(c.stats.estimated, isFalse);
    expect(c.stats.firstTokenMs, isNotNull);
    expect(c.session!.externalSessionId, 's-123');
    expect(File('${dir.path}/args.txt').readAsStringSync().trim(), '--profile headless --json');

    // 第二轮应携带 --session-id
    await c.send(agent, '继续');
    expect(File('${dir.path}/args.txt').readAsStringSync(), contains('--session-id s-123'));

    // 持久化：会话、消息、token 统计
    final sessions = await chats.listSessions();
    expect(sessions.single.hostName, 'web');
    final msgs = await chats.messages(sessions.single.id);
    expect(msgs.map((m) => m.role), ['user', 'assistant', 'user', 'assistant']);
    final now = DateTime.now();
    final sum = await tokens.summary(now, now);
    expect(sum.input, 240);
    expect(sum.output, 60);
    expect(sum.requests, 2);
    expect((await tokens.byModel(now, now)).single.key, 'deepseek-v4');
    expect((await tokens.byAgent(now, now)).single.key, 'DSH');

    // 删除记录
    await chats.deleteSession(sessions.single.id);
    expect(await chats.listSessions(), isEmpty);
    dir.deleteSync(recursive: true);
  });
}
