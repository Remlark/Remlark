import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../../l10n/app_localizations.dart';
import '../agent_config.dart';
import '../agent_interface.dart';
import 'openai_models.dart';

/// OpenAI 兼容 API 的 Agent（接口地址与模型都需要配置，没有默认值）
/// 使用 SSE 流式输出，并通过 stream_options.include_usage 获取 token 用量
class OpenAiCompatibleAgent implements AiAgent {
  OpenAiCompatibleAgent(this.settings);

  final AgentSettings settings;
  http.Client? _client;

  @override
  String get name => settings.name;

  @override
  String get model => settings.model;

  @override
  Stream<AgentEvent> send(AgentRequest request) {
    // 未配置接口地址或模型时直接提示（没有默认值）
    final missing = settings.endpoint.trim().isEmpty
        ? 'agent.endpoint.required'
        : (settings.model.trim().isEmpty ? 'agent.model.required' : null);
    if (missing != null) return Stream.value(AgentError(S.current.t(missing)));
    return _send(request);
  }

  String get _url => '${OpenAiModels.baseUrl(settings.endpoint)}/chat/completions';

  /// 流式请求一轮
  Stream<AgentEvent> _send(AgentRequest request) async* {
    final client = http.Client();
    _client = client;
    final messages = [
      if (request.systemPrompt.isNotEmpty) {'role': 'system', 'content': request.systemPrompt},
      for (final m in request.history) {'role': m.role, 'content': m.content},
      {'role': 'user', 'content': request.prompt},
    ];
    final req = http.Request('POST', Uri.parse(_url))
      ..headers.addAll({
        'Content-Type': 'application/json',
        'Accept': 'text/event-stream',
        ...OpenAiModels.headers(settings.apiKey),
      })
      ..body = jsonEncode({
        'model': model,
        'messages': messages,
        'stream': true,
        'stream_options': {'include_usage': true},
      });
    var output = StringBuffer();
    var gotUsage = false;
    try {
      final resp = await client.send(req);
      if (resp.statusCode != 200) {
        final body = await resp.stream.bytesToString();
        yield AgentError('HTTP ${resp.statusCode}: $body');
        return;
      }
      final lines = resp.stream.transform(utf8.decoder).transform(const LineSplitter());
      await for (final line in lines) {
        if (!line.startsWith('data:')) continue;
        final data = line.substring(5).trim();
        if (data == '[DONE]') break;
        Map<String, dynamic> j;
        try {
          j = jsonDecode(data) as Map<String, dynamic>;
        } catch (_) {
          continue;
        }
        final choices = j['choices'] as List?;
        if (choices != null && choices.isNotEmpty) {
          final delta = (choices.first as Map)['delta'] as Map?;
          final reasoning = delta?['reasoning_content'];
          if (reasoning is String && reasoning.isNotEmpty) {
            yield AgentReasoningDelta(reasoning);
          }
          final content = delta?['content'];
          if (content is String && content.isNotEmpty) {
            output.write(content);
            yield AgentTextDelta(content);
          }
        }
        final usage = j['usage'] as Map?;
        if (usage != null) {
          gotUsage = true;
          final input = (usage['prompt_tokens'] as num?)?.toInt() ?? 0;
          final out = (usage['completion_tokens'] as num?)?.toInt() ?? 0;
          yield AgentUsage(
            inputTokens: input,
            outputTokens: out,
            contextTokens: (usage['total_tokens'] as num?)?.toInt() ?? input + out,
          );
        }
      }
      if (!gotUsage) {
        final input = estimateTokens(messages.map((m) => m['content']).join('\n'));
        final out = estimateTokens(output.toString());
        yield AgentUsage(inputTokens: input, outputTokens: out, estimated: true);
      }
    } catch (e) {
      if (_client != null) yield AgentError('$e');
    } finally {
      client.close();
      _client = null;
    }
  }

  @override
  void cancel() {
    final c = _client;
    _client = null;
    c?.close();
  }
}
