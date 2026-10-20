import 'dart:typed_data';

/// 画面中一块区域的像素（BGRA，行距 = w * 4）
class FramePatch {
  const FramePatch(this.x, this.y, this.w, this.h, this.bgra);

  final int x, y, w, h;
  final Uint8List bgra;
}

/// 一次画面更新：整屏（[full]，patches 为覆盖整屏的一块）或若干变化区域。
/// 区域按顺序覆盖到上一帧上，后面的覆盖前面的
class FrameUpdate {
  const FrameUpdate({required this.width, required this.height, required this.full, required this.patches});

  /// 整屏更新
  FrameUpdate.fullFrame(this.width, this.height, Uint8List bgra)
    : full = true,
      patches = [FramePatch(0, 0, width, height, bgra)];

  final int width;
  final int height;
  final bool full;
  final List<FramePatch> patches;

  /// 依次合并多次更新（遇到整屏更新则丢弃之前的）
  static FrameUpdate? combine(List<FrameUpdate> updates) {
    if (updates.isEmpty) return null;
    if (updates.length == 1) return updates.single;
    var start = 0;
    for (var i = updates.length - 1; i >= 0; i--) {
      if (updates[i].full) {
        start = i;
        break;
      }
    }
    final last = updates.last;
    return FrameUpdate(
      width: last.width,
      height: last.height,
      full: updates[start].full,
      patches: [for (final u in updates.sublist(start)) ...u.patches],
    );
  }
}

/// 变化区域合并：裁剪到画面范围；总面积超过整屏 [fullRatio] 返回 null（改为整屏），
/// 区域数超过 [maxRects] 合并为外接矩形
class DirtyMerge {
  DirtyMerge._();

  static const fullRatio = 0.5;
  static const maxRects = 48;

  static List<(int, int, int, int)>? merge(List<(int, int, int, int)> rects, int w, int h) {
    final clipped = <(int, int, int, int)>[];
    var area = 0;
    var l = w, t = h, r = 0, b = 0;
    for (final (x, y, rw, rh) in rects) {
      final x0 = x.clamp(0, w), y0 = y.clamp(0, h);
      final x1 = (x + rw).clamp(0, w), y1 = (y + rh).clamp(0, h);
      if (x1 <= x0 || y1 <= y0) continue;
      clipped.add((x0, y0, x1 - x0, y1 - y0));
      area += (x1 - x0) * (y1 - y0);
      if (x0 < l) l = x0;
      if (y0 < t) t = y0;
      if (x1 > r) r = x1;
      if (y1 > b) b = y1;
    }
    if (area > w * h * fullRatio) return null;
    if (clipped.length > maxRects) {
      if ((r - l) * (b - t) > w * h * fullRatio) return null;
      return [(l, t, r - l, b - t)];
    }
    return clipped;
  }
}
