import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../../../utils/platform_utils.dart';
import '../agent_config.dart';
import '../agent_interface.dart';

/// DeepSeek Harness CLI（dsh）Agent。
/// 以 headless 模式运行：`dsh --profile headless --json [--session-id <id>]`，
/// 任务通过 stdin 传入，stdout 输出按行分隔的 JSON 事件；
/// 非 JSON 行按普通文本处理（兼容不带 --json 的旧版本）。
/// 上下文由 dsh 自身会话维护（--session-id 续接）。
class DeepSeekCliAgent implements AiAgent {
  DeepSeekCliAgent(this.settings);

  final AgentSettings settings;
  Process? _process;

  @override
  String get name => settings.name;

  @override
  String get model => settings.model.isEmpty ? 'deepseek-harness' : settings.model;

  /// 可执行文件
  String get _executable {
    final cmd = settings.command.trim().isEmpty ? 'dsh' : settings.command.trim();
    if (cmd.contains('/') || cmd.contains('\\')) return cmd;
    return PlatformUtils.which(cmd) ?? cmd;
  }

  /// 构造参数
  List<String> _args(AgentRequest req) {
    final extra = settings.args.trim();
    final args = <String>[
      if (extra.isEmpty) ...['--profile', 'headless', '--json'] else ..._split(extra),
      if (req.externalSessionId != null) ...['--session-id', req.externalSessionId!],
    ];
    return args;
  }

  /// 按空格拆分参数（支持双引号）
  static List<String> _split(String s) {
    final out = <String>[];
    final re = RegExp(r'"([^"]*)"|(\S+)');
    for (final m in re.allMatches(s)) {
      out.add(m.group(1) ?? m.group(2)!);
    }
    return out;
  }

  @override
  Stream<AgentEvent> send(AgentRequest request) async* {
    final controller = StreamController<AgentEvent>();
    _streamedText = false;
    final prompt = request.systemPrompt.isEmpty || request.externalSessionId != null
        ? request.prompt
        : '${request.systemPrompt}\n\n${request.prompt}';
    final env = Map<String, String>.from(Platform.environment);
    if (settings.apiKey?.isNotEmpty == true) {
      env['DEEPSEEK_API_KEY'] = settings.apiKey!;
    }
    Process process;
    try {
      process = await Process.start(_executable, _args(request), environment: env);
    } catch (e) {
      yield AgentError('$e');
      return;
    }
    _process = process;
    process.stdin.write(prompt);
    await process.stdin.close();

    final output = StringBuffer();
    var gotUsage = false;
    final stderrBuf = StringBuffer();

    process.stderr.transform(utf8.decoder).listen(stderrBuf.write);
    process.stdout
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen(
          (line) {
            for (final e in _parseLine(line)) {
              if (e is AgentTextDelta) output.write(e.text);
              if (e is AgentUsage) gotUsage = true;
              controller.add(e);
            }
          },
          onDone: () async {
            final code = await process.exitCode;
            if (!gotUsage) {
              controller.add(
                AgentUsage(
                  inputTokens: estimateTokens(prompt),
                  outputTokens: estimateTokens(output.toString()),
                  estimated: true,
                ),
              );
            }
            if (code != 0 && _process != null) {
              final err = stderrBuf
                  .toString()
                  .split('\n')
                  .where((l) => !l.startsWith('dsh: reasoning'))
                  .join('\n')
                  .trim();
              controller.add(AgentError('exit $code${err.isEmpty ? '' : ': $err'}'));
            }
            _process = null;
            await controller.close();
          },
        );
    yield* controller.stream;
  }

  /// 解析一行输出为事件。兼容多种常见 NDJSON 结构：
  /// {type: text|delta|message|assistant, text|delta|content}
  /// {type: usage|result|done, usage: {input_tokens|prompt_tokens, output_tokens|completion_tokens}}
  /// {session_id|sessionId: ...}
  List<AgentEvent> _parseLine(String line) {
    final trimmed = line.trim();
    if (trimmed.isEmpty) return const [];
    if (!trimmed.startsWith('{')) return [AgentTextDelta('$line\n')];
    Map<String, dynamic> j;
    try {
      j = jsonDecode(trimmed) as Map<String, dynamic>;
    } catch (_) {
      return [AgentTextDelta('$line\n')];
    }
    final events = <AgentEvent>[];
    final type = (j['type'] ?? j['event'] ?? '').toString();
    final sid = j['session_id'] ?? j['sessionId'] ?? (j['session'] is Map ? (j['session'] as Map)['id'] : null);
    if (sid is String && sid.isNotEmpty) events.add(AgentSessionId(sid));

    if (type.contains('reasoning') || type.contains('thinking')) {
      final t = _text(j);
      if (t != null) events.add(AgentReasoningDelta(t));
    } else if (type.contains('error')) {
      events.add(AgentError(_text(j) ?? (j['message'] ?? j['error']).toString()));
    } else if (!type.contains('result') && !type.contains('final')) {
      final t = _text(j);
      if (t != null) events.add(AgentTextDelta(t));
    } else if (!_streamedText) {
      // 只有最终结果事件（未流式输出）时，使用最终文本
      final t = _text(j);
      if (t != null) events.add(AgentTextDelta(t));
    }
    if (events.any((e) => e is AgentTextDelta)) _streamedText = true;

    final usage = (j['usage'] ?? (j['data'] is Map ? (j['data'] as Map)['usage'] : null)) as Map?;
    if (usage != null) {
      final input = _num(usage, ['input_tokens', 'prompt_tokens', 'inputTokens', 'input']);
      final out = _num(usage, ['output_tokens', 'completion_tokens', 'outputTokens', 'output']);
      final ctx = _num(usage, ['context_tokens', 'total_tokens', 'contextTokens']);
      events.add(AgentUsage(inputTokens: input, outputTokens: out, contextTokens: ctx == 0 ? null : ctx));
    }
    return events;
  }

  bool _streamedText = false;

  static int _num(Map m, List<String> keys) {
    for (final k in keys) {
      final v = m[k];
      if (v is num) return v.toInt();
    }
    return 0;
  }

  /// 提取事件中的文本字段
  static String? _text(Map<String, dynamic> j) {
    for (final k in ['delta', 'text', 'content', 'output', 'result']) {
      final v = j[k];
      if (v is String && v.isNotEmpty) return v;
      if (v is Map && v['text'] is String) return v['text'] as String;
      if (v is List) {
        final parts = v.whereType<Map>().map((e) => e['text']).whereType<String>().join();
        if (parts.isNotEmpty) return parts;
      }
    }
    final data = j['data'];
    if (data is Map<String, dynamic>) return _text(data);
    final msg = j['message'];
    if (msg is Map<String, dynamic>) return _text(msg);
    return null;
  }

  @override
  void cancel() {
    final p = _process;
    _process = null;
    p?.kill();
  }
}
