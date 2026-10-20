import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:drift/native.dart';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:remlark/data/database.dart';
import 'package:remlark/modules/ai/agent_config.dart';
import 'package:remlark/modules/ai/agent_interface.dart';
import 'package:remlark/modules/ai/agents/deepseek_harness_agent.dart';
import 'package:remlark/modules/ai/chat_controller.dart';
import 'package:remlark/modules/ai/chat_repository.dart';
import 'package:remlark/modules/ai/dsh/dsh_acp_service.dart';
import 'package:remlark/modules/ai/dsh/dsh_environment.dart';
import 'package:remlark/modules/ai/dsh/dsh_runtime_controller.dart';
import 'package:remlark/modules/ai/dsh/platform/dsh_platform.dart';
import 'package:remlark/modules/ai/token_repository.dart';
import 'package:remlark/modules/ai/terminal_agent/command_permission.dart';
import 'package:remlark/modules/ai/terminal_agent/terminal_driver.dart';

/// 真实安装测试：从 nodejs.org 下载 Node.js、从 npm 安装 dsh，再以 ACP 子进程提问。
/// 需要网络且耗时数分钟（依赖约 1GB），默认跳过；设置 RMK_DSH_E2E=1 运行。
/// 设置 RMK_DSH_E2E_DIR 可复用安装目录（第二次运行跳过下载，只验证“已是最新”与启动）。
void main() {
  final enabled = Platform.environment['RMK_DSH_E2E'] == '1';

  test('下载 Node.js 与 dsh、启动 ACP 子进程、提问（无 API Key 时返回明确错误）', () async {
    final keep = Platform.environment['RMK_DSH_E2E_DIR'];
    final root = keep ?? Directory.systemTemp.createTempSync('rmk_dsh_e2e').path;
    final env = DshEnvironment(p.join(root, 'dsh'), DshPlatform.current());
    final service = DshAcpService(
      launcher: null,
      workspace: () async => env.workspaceDir,
    );
    DshEnvironment.override = env;
    final c = DshRuntimeController(environment: () async => env, service: service);
    try {
      await c.checkUpdate(force: true);
      expect(c.latestVersion, isNotNull);
      if (!c.installed || c.updateAvailable) {
        final ok = await c.install();
        expect(ok, isTrue, reason: c.error);
      }
      expect(c.installedVersion, c.latestVersion);
      expect(env.nodeVersion, isNotNull);
      // 临时目录已清理
      expect(Directory(env.root).listSync().map((e) => p.basename(e.path)).where((n) => n.startsWith('.')), isEmpty);

      // 不带 API Key 提问：握手、新建会话成功，提问返回 dsh 的缺少 Key 错误
      final agent = DeepSeekHarnessAgent(
        const AgentSettings(uuid: 'e2e', name: 'dsh', kind: AgentKind.deepseekCli, apiKey: '', createdAt: 0),
        service: service,
      );
      final events = await agent
          .send(const AgentRequest(history: [], prompt: 'hi'))
          .toList()
          .timeout(const Duration(minutes: 2));
      final sid = events.whereType<AgentSessionId>().single.id;
      expect(sid, isNotEmpty);
      expect(events.whereType<AgentError>().single.message, contains('DEEPSEEK_API_KEY'));
      // 会话记录写在私有 DSH_HOME 中
      expect(Directory(p.join(env.homeDir, 'sessions')).existsSync(), isTrue);
    } finally {
      await service.shutdown();
      DshEnvironment.override = null;
      if (keep == null) Directory(root).deleteSync(recursive: true);
    }
  }, skip: enabled ? false : 'set RMK_DSH_E2E=1', timeout: const Timeout(Duration(minutes: 40)));

  test('真实 dsh 按 JSON 协议操作终端：本机工具已关闭，命令输入终端，输出交回 AI，最后在聊天中回答', () async {
    final keep = Platform.environment['RMK_DSH_E2E_DIR'];
    final root = keep ?? Directory.systemTemp.createTempSync('rmk_dsh_e2e').path;
    final env = DshEnvironment(p.join(root, 'dsh'), DshPlatform.current());
    DshEnvironment.override = env;
    final llm = await _FakeAnthropic.start();
    final service = DshAcpService(
      launcher: (key) => DshAcpService.launchLocal(key, extraEnvironment: {'DEEPSEEK_BASE_URL': llm.url}),
      workspace: () async => env.workspaceDir,
    );
    final runtime = DshRuntimeController(environment: () async => env, service: service);
    final db = AppDatabase(NativeDatabase.memory());
    try {
      await runtime.loadLocal();
      if (!runtime.installed) expect(await runtime.install(), isTrue, reason: runtime.error);
      DshAcpService.shared = service;
      final term = _FakeTerminal();
      final chat = ChatController(chats: ChatRepository(db), tokens: TokenRepository(db), hostName: 'web-01', terminal: term)
        ..permission = CommandPermission.autoAll;
      await chat
          .send(
            const AgentSettings(uuid: 'e2e', name: 'dsh', kind: AgentKind.deepseekCli, apiKey: 'sk-fake', createdAt: 0),
            '帮我看下这台服务器硬盘多大',
          )
          .timeout(const Duration(minutes: 2));

      // 模型看不到本机执行命令、读写文件的工具
      for (final local in ['bash', 'read', 'write', 'edit', 'glob', 'grep']) {
        expect(llm.toolNames.first, isNot(contains(local)));
      }
      // 第一轮提问带有终端协议说明（dsh 新会话的第一条消息）
      expect(llm.firstUser.first, contains('"action":"run"'));
      // 命令输入了终端，输出交回模型，最终回答出现在聊天中
      expect(term.typed, ['df -h /']);
      expect(chat.messages.map((m) => m.role), ['user', 'assistant', 'terminal', 'assistant']);
      expect(chat.messages.last.content, contains('100G'));
      chat.dispose();
    } finally {
      await service.shutdown();
      await llm.close();
      await db.close();
      DshEnvironment.override = null;
      if (keep == null) Directory(root).deleteSync(recursive: true);
    }
  }, skip: enabled ? false : 'set RMK_DSH_E2E=1', timeout: const Timeout(Duration(minutes: 40)));
}

/// 假终端：输入命令后输出 df 结果
class _FakeTerminal implements TerminalDriver {
  final _out = StreamController<String>.broadcast();
  final typed = <String>[];

  @override
  String get hostLabel => 'web-01';

  @override
  bool get connected => true;

  @override
  Stream<String> get output => _out.stream;

  @override
  Stream<String> get userInput => const Stream.empty();

  @override
  void type(String command, {required bool submit}) {
    typed.add(command);
    Future<void>.delayed(const Duration(milliseconds: 50), () {
      _out.add('$command\r\nFilesystem Size Used Avail\r\n/dev/vda1 100G 40G 60G\r\nroot@web-01:~# ');
    });
  }

  @override
  String screenText({int lines = 30}) => 'root@web-01:~# ';
}

/// 假的 Anthropic Messages 服务：收到终端输出前回复 run，收到后用输出作答（均为 JSON 文本）
class _FakeAnthropic {
  _FakeAnthropic._(this._server);

  final HttpServer _server;

  /// 每次请求中模型可用的工具名与第一条用户消息
  final toolNames = <List<String>>[];
  final firstUser = <String>[];

  String get url => 'http://127.0.0.1:${_server.port}';

  static Future<_FakeAnthropic> start() async {
    final f = _FakeAnthropic._(await HttpServer.bind(InternetAddress.loopbackIPv4, 0));
    f._server.listen(f._handle);
    return f;
  }

  /// 消息内容中的文本
  static String _text(Object? content) => content is String
      ? content
      : (content as List).map((b) => b is Map && b['type'] == 'text' ? '${b['text']}' : '').join();

  Future<void> _handle(HttpRequest req) async {
    final body = jsonDecode(await utf8.decodeStream(req)) as Map<String, dynamic>;
    toolNames.add([for (final t in (body['tools'] as List? ?? const [])) '${(t as Map)['name']}']);
    firstUser.add(_text(((body['messages'] as List).first as Map)['content']));
    final all = jsonEncode(body['messages']);
    final last = _text(((body['messages'] as List).last as Map)['content']);
    final String reply;
    if (last.contains('[Terminal output')) {
      final disk = RegExp(r'/dev/vda1 (\S+)').firstMatch(last)?.group(1) ?? '?';
      reply = jsonEncode({'action': 'answer', 'message': '这台服务器硬盘总共 $disk。'});
    } else if (all.contains('"action":"run"') || all.contains('JSON')) {
      reply = jsonEncode({'action': 'run', 'command': 'df -h /', 'message': '查看硬盘'});
    } else {
      reply = 'no protocol';
    }
    final res = req.response;
    res.headers.contentType = ContentType('text', 'event-stream', charset: 'utf-8');
    void ev(String type, Map<String, Object?> data) => res.write('event: $type\ndata: ${jsonEncode({'type': type, ...data})}\n\n');
    ev('message_start', {
      'message': {
        'id': 'msg_${toolNames.length}',
        'type': 'message',
        'role': 'assistant',
        'model': 'fake',
        'content': [],
        'stop_reason': null,
        'stop_sequence': null,
        'usage': {'input_tokens': 10, 'output_tokens': 1},
      },
    });
    ev('content_block_start', {
      'index': 0,
      'content_block': {'type': 'text', 'text': ''},
    });
    ev('content_block_delta', {
      'index': 0,
      'delta': {'type': 'text_delta', 'text': reply},
    });
    ev('content_block_stop', {'index': 0});
    ev('message_delta', {
      'delta': {'stop_reason': 'end_turn', 'stop_sequence': null},
      'usage': {'output_tokens': 5},
    });
    ev('message_stop', {});
    await res.close();
  }

  Future<void> close() => _server.close(force: true);
}
