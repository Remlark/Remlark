import 'dart:convert';

/// Agent 每轮回复的动作
enum TerminalActionType {
  /// 在终端中执行一条命令
  run,

  /// 命令还在运行，等待一段时间后再看新输出
  wait,

  /// 在聊天中给出回答，本次任务结束
  answer,
}

/// 解析后的 Agent 动作
class TerminalAction {
  const TerminalAction(this.type, {this.command = '', this.seconds = 0, this.message = ''});

  final TerminalActionType type;

  /// run：要执行的命令
  final String command;

  /// wait：等待秒数（已限制在合理范围内）
  final int seconds;

  /// 显示给用户的文字（run / wait 为本步说明，answer 为最终回答，Markdown）
  final String message;
}

/// Remlark 与 Agent 之间的终端操作协议（JSON）：
/// Agent 每轮只回复一个 JSON 动作；Remlark 执行后把终端新增输出作为下一轮提问发回，直到 Agent 回复 answer。
/// 命令是否执行完、是否成功由 Agent 根据输出判断，Remlark 只负责输入命令与转交输出。
class TerminalAgentProtocol {
  TerminalAgentProtocol._();

  /// wait 的秒数范围
  static const minWait = 2;
  static const maxWait = 300;

  /// 每次交给 Agent 的终端输出上限（字符，保留末尾）
  static const maxOutput = 12000;

  /// 系统提示词：说明协议与约束（[host] 为当前服务器）
  static String systemPrompt(String host) =>
      '''
You are an assistant embedded in an SSH terminal client. The user has a live interactive shell open on the remote server "$host"; when they say "this server" or "the machine" they mean "$host". You operate that shell by typing commands into it, and the user watches the same terminal and may type into it too.

Reply to EVERY message with exactly one JSON object (you may wrap it in a ```json code block) and nothing else:
{"action":"run","command":"<one shell command>","message":"<one short sentence telling the user what this step does>"}
{"action":"wait","seconds":<$minWait-$maxWait>,"message":"<short note>"}
{"action":"answer","message":"<your reply to the user, Markdown>"}

How it works:
- After "run", the command is typed into the shell. Depending on the user's settings it runs right away or after the user presses Enter (they may edit it first). You then receive the terminal output that appeared since.
- You decide from the output whether the command has finished (the shell prompt is back) and whether it succeeded. If it is still running (installs, downloads, builds), reply "wait" and you will receive the new output after that many seconds.
- If a command is waiting for interactive input (password, confirmation, editor), the user will handle it in the terminal; reply "wait" or explain in "answer". Prefer non-interactive flags (apt -y, --no-pager, systemctl --no-pager) and never start full-screen programs (vim, top without -b, less).
- Run one command per step; you can run as many steps as needed.
- Always finish with "answer": it is the only thing the user reads in the chat, so put the actual answer or a summary of what was done and found there, in the user's language. Answer directly without running anything when no command is needed.
- Do not claim to have run anything you have not run through "run".''';

  /// 用户提问：附上终端当前屏幕，让 Agent 了解提示符与当前目录
  static String userPrompt(String text, String screen) =>
      screen.trim().isEmpty ? text : '$text\n\n[Current terminal screen]\n```text\n${screen.trimRight()}\n```';

  /// 执行或等待后交给 Agent 的终端输出
  static String observation(String output, {required bool afterWait}) {
    final body = output.trim().isEmpty ? '(no new output)' : output.trimRight();
    return '[Terminal output ${afterWait ? 'since the last report' : 'since the command was entered'}]\n'
        '```text\n$body\n```\n'
        'Reply with the next JSON action (run / wait / answer).';
  }

  /// 没有收到 Agent 回复时的重新提问
  static const noReply =
      '[Your previous reply was empty or did not arrive.] Reply again with exactly one JSON action (run / wait / answer).';

  /// 命令未被用户执行（停止或连接断开）时交给 Agent 的说明
  static const notExecuted = '[The command was not executed.] Reply with the next JSON action.';

  /// 解析 Agent 回复；找不到合法动作时把整段文字当作回答（保证普通对话也能显示）
  static TerminalAction parse(String reply) {
    final j = _findJson(reply);
    if (j == null) return TerminalAction(TerminalActionType.answer, message: reply.trim());
    final message = '${j['message'] ?? ''}'.trim();
    switch ('${j['action']}'.toLowerCase()) {
      case 'run':
        final cmd = '${j['command'] ?? ''}'.trim();
        if (cmd.isEmpty) return TerminalAction(TerminalActionType.answer, message: message);
        return TerminalAction(TerminalActionType.run, command: cmd, message: message);
      case 'wait':
        final s = j['seconds'];
        final secs = (s is num ? s.toInt() : int.tryParse('$s') ?? 10).clamp(minWait, maxWait);
        return TerminalAction(TerminalActionType.wait, seconds: secs, message: message);
      default:
        return TerminalAction(TerminalActionType.answer, message: message.isEmpty ? reply.trim() : message);
    }
  }

  /// 在回复中找含 action 字段的 JSON 对象：优先 ```json 代码块，其次第一个到最后一个花括号之间的内容
  static Map<String, dynamic>? _findJson(String s) {
    final candidates = <String>[
      for (final m in RegExp(r'```(?:json)?\s*\n?([\s\S]*?)```').allMatches(s)) m.group(1)!,
      if (s.contains('{') && s.lastIndexOf('}') > s.indexOf('{')) s.substring(s.indexOf('{'), s.lastIndexOf('}') + 1),
    ];
    for (final c in candidates) {
      try {
        final v = jsonDecode(c.trim());
        if (v is Map<String, dynamic> && v['action'] != null) return v;
      } catch (_) {
        // 不是合法 JSON，尝试下一个
      }
    }
    return null;
  }
}
