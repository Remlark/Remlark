import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../../l10n/app_localizations.dart';
import '../runtime/agent_options.dart';

/// OpenAI 兼容接口的地址与模型列表（各家兼容 `/models` 与 `/chat/completions` 的接口、Ollama 等）。
/// 没有默认地址与默认模型：都需要用户填写或选择
class OpenAiModels {
  OpenAiModels._();

  /// 查询超时
  static const timeout = Duration(seconds: 20);

  /// 接口根地址：去掉末尾的 / 与 /chat/completions（用户可能填写完整的对话地址）。未填写时抛出异常
  static String baseUrl(String endpoint) {
    var base = endpoint.trim();
    if (base.isEmpty) throw S.current.t('agent.endpoint.required');
    while (base.endsWith('/')) {
      base = base.substring(0, base.length - 1);
    }
    const suffix = '/chat/completions';
    return base.endsWith(suffix) ? base.substring(0, base.length - suffix.length) : base;
  }

  /// 请求头：填写了 API Key 时带上 Bearer 认证（本地服务如 Ollama 可不填）
  static Map<String, String> headers(String? apiKey) => {
    if (apiKey != null && apiKey.isNotEmpty) 'Authorization': 'Bearer $apiKey',
  };

  /// 读取接口提供的模型 id（`GET /models`，按名称排序）。失败时抛出异常（消息含 HTTP 状态或原因）
  static Future<List<String>> list(String endpoint, String? apiKey, {http.Client? client}) async {
    final c = client ?? http.Client();
    try {
      final r = await c
          .get(Uri.parse('${baseUrl(endpoint)}/models'), headers: {'Accept': 'application/json', ...headers(apiKey)})
          .timeout(timeout);
      if (r.statusCode != 200) {
        final body = utf8.decode(r.bodyBytes);
        throw 'HTTP ${r.statusCode}${body.isEmpty ? '' : ': ${body.length > 200 ? body.substring(0, 200) : body}'}';
      }
      final data = (jsonDecode(utf8.decode(r.bodyBytes)) as Map)['data'];
      if (data is! List) return const [];
      return [
        for (final m in data)
          if (m is Map && m['id'] != null && '${m['id']}'.isNotEmpty) '${m['id']}',
      ]..sort();
    } finally {
      if (client == null) c.close();
    }
  }

  /// 转换为聊天窗口使用的可选项：没有“默认模型”项（必须选择模型），推理强度不可选择
  static Future<AgentOptions> options(String endpoint, String? apiKey) async =>
      AgentOptions([for (final id in await list(endpoint, apiKey)) AgentModelOption(id: id, label: id)], hasDefault: false);
}
