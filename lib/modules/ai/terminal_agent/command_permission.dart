import 'read_only_commands.dart';

/// AI 在终端中执行命令的权限模式（聊天底部切换，每个终端标签页独立）
enum CommandPermission {
  /// 只给建议：AI 不操作终端，只在回答中给出命令，由用户发送到终端
  suggestOnly,

  /// 逐条确认（默认）：命令填入终端但不回车，用户检查（可修改）后按回车执行
  ask,

  /// 只读自动执行：只读命令直接执行，其他命令同“逐条确认”
  autoReadOnly,

  /// 全部自动执行：命令填入终端并直接回车
  autoAll;

  /// AI 是否操作终端
  bool get operatesTerminal => this != suggestOnly;

  /// [command] 是否直接回车执行（否则等待用户按回车）
  bool autoSubmits(String command) => switch (this) {
    suggestOnly || ask => false,
    autoReadOnly => ReadOnlyCommands.isReadOnly(command),
    autoAll => true,
  };
}
