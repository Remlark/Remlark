import 'package:flutter_test/flutter_test.dart';
import 'package:remlark/modules/terminal/reflow_safe_terminal.dart';
import 'package:xterm/xterm.dart';

/// 验证真实终端模型中的颜色及属性，包含 SSH 任意分块边界。
void main() {
  for (final reset in ['\x1b[0m', '\x1b[m']) {
    test('完整重置 $reset 在所有分块边界清除颜色及格式', () {
      final output = '\x1b[1;2;3;4;5;7;8;9;35;43mA${reset}B';
      for (var split = 0; split <= output.length; split++) {
        final terminal = ReflowSafeTerminal();
        terminal.write(output.substring(0, split));
        terminal.write(output.substring(split));
        final cell = CellData.empty();
        terminal.buffer.lines[0].getCellData(1, cell);
        expect(cell.foreground, 0, reason: 'split=$split');
        expect(cell.background, 0, reason: 'split=$split');
        expect(cell.flags, 0, reason: 'split=$split');
      }
    });
  }

  test('SGR 22 同时关闭粗体和淡化，保留颜色与其他属性', () {
    final terminal = ReflowSafeTerminal();
    terminal.write('\x1b[1;2;3;35mA\x1b[22mB');
    expect(terminal.cursor.isBold, isFalse);
    expect(terminal.cursor.isFaint, isFalse);
    expect(terminal.cursor.isItalis, isTrue);
    expect(terminal.cursor.foreground, isNot(0));
  });

  test('前景及背景独立重置不影响其他属性', () {
    final terminal = ReflowSafeTerminal();
    terminal.write('\x1b[1;31;43mA\x1b[39mB');
    expect(terminal.cursor.foreground, 0);
    expect(terminal.cursor.background, isNot(0));
    expect(terminal.cursor.isBold, isTrue);
    terminal.write('\x1b[49mC');
    expect(terminal.cursor.background, 0);
    expect(terminal.cursor.isBold, isTrue);
  });

  test('未收到重置时颜色按终端协议跨行和分块保留', () {
    final terminal = ReflowSafeTerminal();
    terminal.write('\x1b[35mA\r\n');
    final foreground = terminal.cursor.foreground;
    terminal.write('B');
    expect(terminal.cursor.foreground, foreground);
    expect(foreground, isNot(0));
  });
}
