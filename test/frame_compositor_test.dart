import 'dart:ui' as ui;

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:remlark/modules/remote_desktop/remote_display.dart';
import 'package:remlark/modules/remote_desktop/ui/frame_compositor.dart';

/// 假显示源：按测试需要排队的画面更新
class _FakeDisplay extends ChangeNotifier implements RemoteDisplay {
  final List<FrameUpdate> queue = [];

  @override
  FrameUpdate? takeFrame() => queue.isEmpty ? null : queue.removeAt(0);

  @override
  bool get displayReady => true;
  @override
  int get frameWidth => 100;
  @override
  int get frameHeight => 80;
  @override
  RemoteCursor? get cursor => null;
  @override
  void pointerEvent(int x, int y, int buttons) {}
  @override
  void scrollEvent(int x, int y, int steps) {}
  @override
  KeyEventResult keyEvent(KeyEvent event) => KeyEventResult.ignored;
  @override
  void displayFocused() {}
  @override
  void displayBlurred() {}
  @override
  void viewResized(int width, int height) {}
}

/// 纯色像素块（BGRA）
Uint8List _solid(int w, int h, List<int> bgra) {
  final out = Uint8List(w * h * 4);
  for (var i = 0; i < w * h; i++) {
    out.setAll(i * 4, bgra);
  }
  return out;
}

Future<List<int>> _pixel(ui.Image img, int x, int y) async {
  final data = (await img.toByteData(format: ui.ImageByteFormat.rawRgba))!;
  final o = (y * img.width + x) * 4;
  return [data.getUint8(o), data.getUint8(o + 1), data.getUint8(o + 2), data.getUint8(o + 3)];
}

void main() {
  testWidgets('整屏解码；之后只把变化区域覆盖到上一帧，其余像素不变；无更新返回 null', (tester) async {
    await tester.runAsync(() async {
      final d = _FakeDisplay();
      final c = FrameCompositor();
      expect(await c.next(d, null), isNull);

      d.queue.add(FrameUpdate.fullFrame(100, 80, _solid(100, 80, [0, 0, 255, 255]))); // 红色（BGRA）
      final first = (await c.next(d, null))!;
      expect(await _pixel(first, 50, 40), [255, 0, 0, 255]);

      // 两个区域按顺序覆盖：后者覆盖前者的重叠部分
      d.queue.add(
        FrameUpdate(
          width: 100,
          height: 80,
          full: false,
          patches: [
            FramePatch(0, 0, 10, 10, _solid(10, 10, [0, 255, 0, 255])),
            FramePatch(5, 5, 10, 10, _solid(10, 10, [255, 0, 0, 255])),
          ],
        ),
      );
      final second = (await c.next(d, first))!;
      expect(await _pixel(second, 2, 2), [0, 255, 0, 255]);
      expect(await _pixel(second, 7, 7), [0, 0, 255, 255]);
      expect(await _pixel(second, 50, 40), [255, 0, 0, 255]);
      expect(c.statFull, 1);
      expect(c.statRects, 2);
      for (final img in [first, second]) {
        img.dispose();
      }
    });
  });

  test('多次更新合并：遇到整屏丢弃之前的区域', () {
    FrameUpdate part(int x) =>
        FrameUpdate(width: 4, height: 4, full: false, patches: [FramePatch(x, 0, 1, 1, Uint8List(4))]);
    final merged = FrameUpdate.combine([part(0), FrameUpdate.fullFrame(4, 4, Uint8List(64)), part(1), part(2)])!;
    expect(merged.full, isTrue);
    expect(merged.patches.map((p) => p.x), [0, 1, 2]);
    expect(merged.patches.first.w, 4);
    final parts = FrameUpdate.combine([part(0), part(1)])!;
    expect(parts.full, isFalse);
    expect(parts.patches, hasLength(2));
  });
}
