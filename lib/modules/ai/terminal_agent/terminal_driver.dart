/// AI 操作终端所需的终端能力（由终端模块用 TerminalSession 实现，AI 模块只依赖此接口）
abstract class TerminalDriver {
  /// 服务器显示名
  String get hostLabel;

  /// 终端当前是否已连接
  bool get connected;

  /// shell 原始输出（含控制序列）
  Stream<String> get output;

  /// 用户在该终端中的键盘输入（用于“逐条确认”时等待用户按回车）
  Stream<String> get userInput;

  /// 把 [command] 输入到 shell（不经过广播）；[submit] 为 true 时同时按回车
  void type(String command, {required bool submit});

  /// 当前屏幕上最后 [lines] 行的纯文本（让 AI 了解提示符、当前目录等）
  String screenText({int lines = 30});
}
