import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:remlark/modules/remote_desktop/vnc/move_throttle.dart';

void main() {
  test('鼠标移动限流：首个立即发送，之后每 16ms 只发最新位置，空闲后停止', () {
    fakeAsync((async) {
      final sent = <(int, int)>[];
      final t = MoveThrottle((x, y) => sent.add((x, y)));
      // 1 秒内 400 次移动（每 2.5ms 一次）
      for (var i = 0; i < 400; i++) {
        t.move(i, i);
        async.elapse(const Duration(microseconds: 2500));
      }
      async.elapse(const Duration(milliseconds: 50));
      expect(sent.first, (0, 0));
      expect(sent.last, (399, 399), reason: '最后的位置不能丢');
      expect(sent.length, lessThanOrEqualTo(70), reason: '约 60Hz');
      final n = sent.length;
      async.elapse(const Duration(seconds: 1));
      expect(sent.length, n, reason: '没有新移动时不再发送');
      // drop：按键变化时丢弃未发送的移动
      t.move(1000, 1000);
      t.move(1001, 1001);
      t.drop();
      async.elapse(const Duration(milliseconds: 50));
      expect(sent.last, isNot((1001, 1001)));
      t.cancel();
    });
  });
}
