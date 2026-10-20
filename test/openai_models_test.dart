import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:remlark/modules/ai/agent_config.dart';
import 'package:remlark/modules/ai/agent_options_controller.dart';
import 'package:remlark/modules/ai/agent_interface.dart';
import 'package:remlark/modules/ai/agents/openai_compatible_agent.dart';
import 'package:remlark/modules/ai/agents/openai_models.dart';
import 'package:remlark/modules/ai/runtime/agent_runtime.dart';

void main() {
  test('接口根地址：没有默认地址，去掉末尾 / 与 /chat/completions', () {
    expect(() => OpenAiModels.baseUrl(''), throwsA(isA<String>()));
    expect(OpenAiModels.baseUrl('http://localhost:11434/v1/'), 'http://localhost:11434/v1');
    expect(OpenAiModels.baseUrl('https://x.com/v1/chat/completions'), 'https://x.com/v1');
  });

  test('读取 /models：带 API Key、按名称排序；聊天中可选择，没有默认项、推理强度不可选', () async {
    String? auth;
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((req) async {
      auth = req.headers.value('authorization');
      if (req.uri.path == '/v1/models') {
        req.response.write(jsonEncode({
          'data': [
            {'id': 'qwen3'},
            {'id': 'llama3.2'},
          ],
        }));
      } else {
        req.response.statusCode = 401;
        req.response.write('unauthorized');
      }
      await req.response.close();
    });
    final endpoint = 'http://127.0.0.1:${server.port}/v1';
    expect(await OpenAiModels.list(endpoint, 'sk-x'), ['llama3.2', 'qwen3']);
    expect(auth, 'Bearer sk-x');
    // 本地服务不填 API Key 时不带认证头
    await OpenAiModels.list(endpoint, null);
    expect(auth, isNull);
    await expectLater(OpenAiModels.list('http://127.0.0.1:${server.port}/bad', null), throwsA(contains('HTTP 401')));

    final options = AgentOptionsController(AgentRuntimes({}));
    final agent = AgentSettings(uuid: 'o1', name: 'Ollama', kind: AgentKind.openaiApi, endpoint: endpoint, createdAt: 0);
    expect(options.supports(agent), isTrue);
    await options.load(agent);
    final opts = options.of('o1')!;
    expect(opts.models.map((m) => m.id), ['llama3.2', 'qwen3']);
    expect(opts.hasDefault, isFalse);
    expect(opts.modelFor(''), isNull);
    expect(opts.models.first.efforts, isEmpty);
    await server.close(force: true);
  });

  test('未配置接口地址或模型时直接提示，不发请求', () async {
    const noEndpoint = AgentSettings(uuid: 'o', name: 'x', kind: AgentKind.openaiApi, model: 'm', createdAt: 0);
    const noModel = AgentSettings(uuid: 'o', name: 'x', kind: AgentKind.openaiApi, endpoint: 'http://127.0.0.1:1', createdAt: 0);
    for (final s in [noEndpoint, noModel]) {
      final events = await OpenAiCompatibleAgent(s).send(const AgentRequest(history: [], prompt: 'hi')).toList();
      expect(events.single, isA<AgentError>());
    }
  });
}
