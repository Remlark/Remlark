import 'package:flutter_test/flutter_test.dart';
import 'package:remlark/modules/terminal/reflow_safe_terminal.dart';
import 'package:xterm/xterm.dart';

// 对照 GORM v1.25.12 logger.traceErrStr：重置位于第二行开头。
const _log =
    '2026/10/25 \x1b[31;1mdb.go:57 '
    '\x1b[35;1mdial tcp: no route to host\r\n'
    '\x1b[0m\x1b[33m[0.232ms] \x1b[34;1m[rows:-]\x1b[0m SELECT 1\r\n';

/// 模拟按行 grep 的内容筛选；不调用系统命令，所有平台使用相同输入。
String _filterLog(String input) => input
    .split('\r\n')
    .where((line) => line.contains('dial tcp'))
    .map((line) => '$line\r\n')
    .join();

/// 检查下一行提示符的实际样式，复现日志筛选丢失重置的情形。
void _expectPrompt(Terminal terminal, {int foreground = 0, int flags = 0}) {
  final cell = CellData.empty();
  terminal.buffer.lines[terminal.buffer.absoluteCursorY].getCellData(0, cell);
  expect(cell.foreground, foreground);
  expect(cell.background, 0);
  expect(cell.flags, flags);
}

/// 验证截图对应的跨行颜色来源及完整日志、补发重置后的恢复行为。
void main() {
  test('完整 GORM 两行日志结束后提示符无格式残留', () {
    final terminal = ReflowSafeTerminal()..write('${_log}host\$ ');
    _expectPrompt(terminal);
  });

  test('筛掉 SQL 行会丢失重置，复现紫色粗体提示符', () {
    final filtered = _filterLog(_log);
    expect(filtered.contains('\x1b[0m'), isFalse);
    final terminal = ReflowSafeTerminal()..write('${filtered}host\$ ');
    _expectPrompt(terminal, foreground: CellColor.named | 5, flags: 1);
  });

  test('筛选命令结束后补发完整重置可恢复普通提示符', () {
    final output = '${_filterLog(_log)}\x1b[0mhost\$ ';
    // 遍历全部分包位置，确保补发重置也能跨 SSH 包正确生效。
    for (var split = 0; split <= output.length; split++) {
      final terminal = ReflowSafeTerminal()
        ..write(output.substring(0, split))
        ..write(output.substring(split));
      _expectPrompt(terminal);
    }
  });
}
