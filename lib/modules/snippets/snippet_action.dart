import '../hosts/host_repository.dart';
import '../terminal/terminal_session.dart';
import 'actions/install_system_key_action.dart';
import 'snippet_model.dart';

/// 快捷指令执行上下文
class SnippetContext {
  SnippetContext({required this.session, required this.hosts, required this.log});

  /// 目标终端会话
  final TerminalSession session;
  final HostRepository hosts;

  /// 执行日志输出（显示在执行对话框中）
  final void Function(String line) log;
}

/// 快捷指令动作接口：普通字符串与特殊动作（多步骤）都实现该接口，
/// 后续扩展新的特殊快捷指令只需新增实现并在 [forSnippet] 注册
abstract class SnippetAction {
  /// 是否需要显示执行进度对话框（多步骤动作）
  bool get showsProgress;

  /// 当前平台是否可用
  bool get isAvailable => true;

  /// 执行
  Future<void> run(SnippetContext ctx);

  /// 根据快捷指令创建对应动作
  static SnippetAction forSnippet(SnippetEntry s) {
    switch (s.kind) {
      case SnippetKind.text:
        return TextSnippetAction(s);
      case SnippetKind.installSystemKey:
        return InstallSystemKeyAction();
    }
  }
}

/// 普通字符串：直接输入到终端
class TextSnippetAction extends SnippetAction {
  TextSnippetAction(this.snippet);

  final SnippetEntry snippet;

  @override
  bool get showsProgress => false;

  @override
  Future<void> run(SnippetContext ctx) async {
    ctx.session.sendRaw(snippet.content + (snippet.autoEnter ? '\r' : ''));
  }
}
