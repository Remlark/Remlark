import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:remlark/modules/terminal/reflow_safe_terminal.dart';
import 'package:xterm/xterm.dart';

const _attributes = [
  (name: '粗体', on: 1, off: 22, bit: 1),
  (name: '淡化', on: 2, off: 22, bit: 2),
  (name: '斜体', on: 3, off: 23, bit: 4),
  (name: '下划线', on: 4, off: 24, bit: 8),
  (name: '闪烁', on: 5, off: 25, bit: 16),
  (name: '反色', on: 7, off: 27, bit: 32),
  (name: '隐藏', on: 8, off: 28, bit: 64),
  (name: '删除线', on: 9, off: 29, bit: 128),
];

/// 检查实际缓冲区单元，避免仅检查光标而漏掉已写入文本的格式残留。
void _expectStyle(
  Terminal terminal,
  int x, {
  int y = 0,
  int foreground = 0,
  int background = 0,
  int flags = 0,
}) {
  final cell = CellData.empty();
  terminal.buffer.lines[y].getCellData(x, cell);
  expect(
    (cell.foreground, cell.background, cell.flags),
    (foreground, background, flags),
    reason: 'cell=($x,$y)',
  );
}

/// 覆盖全部属性组合、调色板及真彩色的关闭与重置语义。
void main() {
  for (final attribute in _attributes) {
    test('${attribute.name} 单独关闭及所有分包边界', () {
      final output = '\x1b[${attribute.on}mA\x1b[${attribute.off}mB';
      for (var split = 0; split <= output.length; split++) {
        final terminal = ReflowSafeTerminal();
        terminal.write(output.substring(0, split));
        terminal.write(output.substring(split));
        _expectStyle(terminal, 0, flags: attribute.bit);
        _expectStyle(terminal, 1);
      }
    });
    test('${attribute.name} 从全部属性中关闭，不误清其他格式', () {
      final terminal = ReflowSafeTerminal();
      terminal.write('\x1b[1;2;3;4;5;7;8;9;31;44mA');
      final foreground = terminal.cursor.foreground;
      final background = terminal.cursor.background;
      terminal.write('\x1b[${attribute.off}mB');
      final removed = attribute.off == 22 ? 3 : attribute.bit;
      _expectStyle(
        terminal,
        1,
        foreground: foreground,
        background: background,
        flags: 255 & ~removed,
      );
      terminal.write('\x1b[0mC');
      _expectStyle(terminal, 2);
    });
  }

  for (final reset in ['0', '']) {
    test('SGR [$reset m 清除全部 256 种属性组合', () {
      for (var mask = 0; mask < 256; mask++) {
        final terminal = ReflowSafeTerminal();
        final codes = _attributes
            .where((a) => mask & a.bit != 0)
            .map((a) => a.on)
            .join(';');
        terminal.write('\x1b[${codes.isEmpty ? '0' : codes}mA');
        _expectStyle(terminal, 0, flags: mask);
        terminal.write('\x1b[${reset}mB');
        _expectStyle(terminal, 1);
        // 重置不能追溯修改之前已输出的字符。
        _expectStyle(terminal, 0, flags: mask);
      }
    });
  }

  for (final background in [false, true]) {
    final label = background ? '背景' : '前景';
    final prefix = background ? 48 : 38;
    final reset = background ? 49 : 39;
    final colors = <(String, int)>[
      for (var i = 0; i < 16; i++)
        (
          '${(background ? 40 : 30) + (i < 8 ? i : 60 + i - 8)}',
          CellColor.named | i,
        ),
      for (var i = 0; i < 256; i++) ('$prefix;5;$i', CellColor.palette | i),
      for (final rgb in [
        (0, 0, 0),
        (255, 255, 255),
        (255, 0, 0),
        (0, 255, 0),
        (0, 0, 255),
        (12, 123, 234),
      ])
        (
          '$prefix;2;${rgb.$1};${rgb.$2};${rgb.$3}',
          CellColor.rgb | rgb.$1 << 16 | rgb.$2 << 8 | rgb.$3,
        ),
    ];
    test('$label 16 色、全部 256 色及 RGB 独立重置与完整重置', () {
      for (final color in colors) {
        for (final end in ['$reset', '0', '']) {
          final terminal = ReflowSafeTerminal();
          terminal.write('\x1b[${color.$1}mA');
          _expectStyle(
            terminal,
            0,
            foreground: background ? 0 : color.$2,
            background: background ? color.$2 : 0,
          );
          terminal.write('\x1b[${end}mB');
          _expectStyle(terminal, 1);
        }
      }
    });
  }

  test('复合 SGR 按参数顺序处理，重置后仅应用新格式', () {
    final terminal = ReflowSafeTerminal();
    terminal.write('\x1b[1;3;31;44mA\x1b[0;4;32mB');
    _expectStyle(terminal, 1, foreground: CellColor.named | 2, flags: 8);
    terminal.write('\x1b[31;1;0mC');
    _expectStyle(terminal, 2);
    terminal.write('\x1b[1;22;3;23;4;24;38;5;200;39;48;2;1;2;3;49mD');
    _expectStyle(terminal, 3);
  });

  test('彩色日志、中文、换行及提示符逐字符和随机分包后没有格式残留', () {
    const output =
        '\x1b[1;35mERROR\x1b[0m normal\r\n'
        '\x1b[3;4;38;2;12;123;234;48;5;200m中文\x1b[m\r\n'
        '\x1b[7;8;9mhidden\x1b[27;28;29m visible\r\n'
        'host\$ ';
    for (var seed = 0; seed < 100; seed++) {
      final terminal = ReflowSafeTerminal();
      final random = Random(seed);
      for (var offset = 0; offset < output.length;) {
        final end = min(
          output.length,
          offset + (seed == 0 ? 1 : 1 + random.nextInt(12)),
        );
        terminal.write(output.substring(offset, end));
        offset = end;
      }
      for (var x = 5; x < 12; x++) {
        _expectStyle(terminal, x);
      }
      for (var x = 6; x < 14; x++) {
        _expectStyle(terminal, x, y: 2);
      }
      for (var x = 0; x < 6; x++) {
        _expectStyle(terminal, x, y: 3);
      }
      expect(terminal.buffer.lines[3].getText().trimRight(), 'host\$');
    }
  });

  test('光标保存恢复后显式重置仍能清除恢复的格式', () {
    final terminal = ReflowSafeTerminal();
    terminal.write('\x1b[1;35;44m\x1b7\x1b[0mA\x1b8B\x1b[0mC');
    _expectStyle(
      terminal,
      0,
      foreground: CellColor.named | 5,
      background: CellColor.named | 4,
      flags: 1,
    );
    _expectStyle(terminal, 1);
  });

  test('两个终端会话之间不共享颜色和格式', () {
    final first = ReflowSafeTerminal();
    final second = ReflowSafeTerminal();
    first.write('\x1b[1;3;4;35;44mA');
    second.write('B');
    _expectStyle(second, 0);
    first.write('\x1b[0mC');
    _expectStyle(first, 1);
  });
}
