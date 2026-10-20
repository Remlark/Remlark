/// 终端输出文本处理：把 shell 原始输出转成给 AI 阅读的纯文本
class AnsiUtils {
  AnsiUtils._();

  /// CSI（ESC [ …）、OSC（ESC ] … BEL / ST）、其他两字节 ESC 序列
  static final _escape = RegExp(r'\x1b\[[0-?]*[ -/]*[@-~]|\x1b\][^\x07\x1b]*(\x07|\x1b\\)|\x1b[PX^_][^\x1b]*\x1b\\|\x1b[@-Z\\-_]|\x1b[()][0-9A-Za-z]');

  /// 去掉控制序列，并按终端行为处理回车覆盖（进度条只保留最后状态）与退格
  static String toPlainText(String raw) {
    final text = raw.replaceAll(_escape, '').replaceAll('\r\n', '\n');
    final lines = <String>[];
    for (final line in text.split('\n')) {
      // 行内 \r：光标回到行首，后面的内容覆盖前面（取最后一段非空内容覆盖的结果）
      var cur = '';
      for (final seg in line.split('\r')) {
        if (seg.isEmpty) continue;
        cur = seg.length >= cur.length ? seg : seg + cur.substring(seg.length);
      }
      lines.add(_applyBackspace(cur).replaceAll(RegExp(r'[\x00-\x08\x0b-\x1f\x7f]'), ''));
    }
    return lines.join('\n');
  }

  /// 处理退格：删除前一个字符
  static String _applyBackspace(String s) {
    if (!s.contains('\b')) return s;
    final b = StringBuffer();
    final chars = <int>[];
    for (final c in s.runes) {
      if (c == 8) {
        if (chars.isNotEmpty) chars.removeLast();
      } else {
        chars.add(c);
      }
    }
    b.write(String.fromCharCodes(chars));
    return b.toString();
  }

  /// 文本过长时只保留末尾 [max] 个字符（终端输出的结尾最有用），开头注明省略了多少
  static String tail(String s, int max) {
    if (s.length <= max) return s;
    return '… [${s.length - max} earlier characters omitted]\n${s.substring(s.length - max)}';
  }
}
