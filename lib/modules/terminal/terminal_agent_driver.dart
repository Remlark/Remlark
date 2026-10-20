import '../ai/terminal_agent/terminal_driver.dart';
import '../workspace/workspace_tab.dart';
import 'terminal_session.dart';

/// 让 AI 操作终端会话：命令直接写入该会话的 shell（不经过广播），输出与用户输入来自会话的流
class TerminalAgentDriver implements TerminalDriver {
  TerminalAgentDriver(this.session);

  final TerminalSession session;

  @override
  String get hostLabel => session.host.name;

  @override
  bool get connected => session.state == SessionState.connected;

  @override
  Stream<String> get output => session.output;

  @override
  Stream<String> get userInput => session.userInput;

  @override
  void type(String command, {required bool submit}) {
    // shell 开启 bracketed paste 时按粘贴发送：多行命令不会逐行执行，也不会触发补全
    final text = session.terminal.bracketedPasteMode ? '\x1b[200~$command\x1b[201~' : command;
    session.sendRaw(submit ? '$text\r' : text);
  }

  @override
  String screenText({int lines = 30}) => session.recentText(lines: lines);
}
