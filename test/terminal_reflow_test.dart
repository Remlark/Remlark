import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:remlark/modules/terminal/reflow_safe_terminal.dart';

void main() {
  test('反复调整宽高后光标仍停在提示符末尾（不漂移到屏幕中间）', () {
    for (var seed = 0; seed < 30; seed++) {
      final rnd = Random(seed);
      final t = ReflowSafeTerminal(maxLines: 20000);
      t.resize(150, 40);
      t.write('Last login: Tue Oct 20 00:23:19 2026\r\r\n\r\n');
      for (var i = 0; i < 5; i++) {
        t.write('${'x' * rnd.nextInt(300)}\r\n');
      }
      t.write('PROMPT\$ ab');
      for (var k = 0; k < 200; k++) {
        t.resize(20 + rnd.nextInt(170), 5 + rnd.nextInt(45));
      }
      t.resize(150, 40);
      final b = t.buffer;
      expect(b.lines[b.absoluteCursorY].getText().trimRight(), 'PROMPT\$ ab', reason: 'seed $seed');
      expect(b.cursorX, 10, reason: 'seed $seed');
      for (var i = b.absoluteCursorY + 1; i < b.lines.length; i++) {
        expect(b.lines[i].getText().trim(), '', reason: 'seed $seed');
      }
    }
  });
}
