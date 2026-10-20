import 'package:flutter_test/flutter_test.dart';
import 'package:remlark/modules/remote_desktop/ui/scroll_accumulator.dart';

void main() {
  test('鼠标滚轮：完整一格至少滚一格，快速滚动按比例多滚，有上限；平滑滚轮细小位移累积', () {
    final a = ScrollAccumulator();
    expect(a.addWheel(-40), -1);
    expect(a.addWheel(120), 2);
    expect(a.addWheel(-260), -5);
    expect(a.addWheel(100000), 10);
    // 平滑滚轮：每个事件 3 像素，约 17 个事件才滚 1 格
    final b = ScrollAccumulator();
    final steps = [for (var i = 0; i < 100; i++) b.addWheel(3)];
    expect(steps.where((s) => s != 0).length, 6);
    expect(steps.reduce((x, y) => x + y), 6);
  });

  test('触控板：累积满 50 像素发 1 格并清零（noVNC），每个事件最多 1 格，方向反转丢弃余数', () {
    final a = ScrollAccumulator();
    expect([for (var i = 0; i < 6; i++) a.add(10)], [0, 0, 0, 0, 1, 0]);
    expect(a.add(400), 1, reason: '大位移也只发 1 格，节奏跟随事件');
    expect(a.add(30), 0, reason: '发送后余数清零');
    expect(a.add(-30), 0);
    expect(a.add(-30), -1);
  });
}
