import 'dart:async';

import '../frame_update.dart';

/// 画面静止后的区域补刷新。
///
/// macOS 的 VNC 服务端经常漏报动画的最终状态（菜单淡入淡出、通知横幅滑入滑出、菜单栏图标变化），
/// 增量更新只发出中间帧，最终画面残留在客户端。这里记录所有增量更新涉及的区域，
/// 画面停止变化 [quiet] 后对这些区域请求一次完整画面（非增量），取到最终状态。
///
/// 防循环：补刷新的结果本身也会作为变化到达，[guard] 时间内落在已补刷新区域内的变化不再记录
class SettleRefresher {
  SettleRefresher({
    required this.refresh,
    this.quiet = const Duration(milliseconds: 250),
    this.inputQuiet = const Duration(milliseconds: 30),
    this.inputWindow = const Duration(milliseconds: 500),
    this.guard = const Duration(milliseconds: 1000),
    this.margin = 16,
  });

  /// 请求补刷新的区域（已合并、外扩）
  final void Function(List<(int, int, int, int)> rects) refresh;

  /// 画面静止多久后补刷新
  final Duration quiet;

  /// 用户输入后 [inputWindow] 内改用更短的静止时间：点击后菜单尽快完整显示
  final Duration inputQuiet;
  final Duration inputWindow;

  /// 补刷新后多久内忽略已补刷新区域内的变化
  final Duration guard;

  /// 补刷新区域外扩像素（覆盖阴影与边框）
  final int margin;

  final _clock = Stopwatch()..start();
  final List<(int, int, int, int)> _pending = [];
  List<(int, int, int, int)> _guarded = const [];
  int _guardUntil = 0;
  int _inputUntil = 0;
  int _width = 0, _height = 0;
  Timer? _timer;

  /// 用户输入（点击、按键、滚轮）
  void noteInput() => _inputUntil = _clock.elapsedMilliseconds + inputWindow.inMilliseconds;

  /// 记录一批增量更新的变化区域（整屏更新不需要补刷新，不调用）
  void noteChanges(List<(int, int, int, int)> rects, int width, int height) {
    _width = width;
    _height = height;
    final now = _clock.elapsedMilliseconds;
    var added = false;
    for (final r in rects) {
      if (now < _guardUntil && _guarded.any((g) => _contains(g, r))) continue;
      _pending.add(r);
      added = true;
    }
    if (!added) return;
    // 每次有新变化重新计时，画面静止后才补刷新
    _timer?.cancel();
    _timer = Timer(now < _inputUntil ? inputQuiet : quiet, _flush);
  }

  void _flush() {
    if (_pending.isEmpty || _width <= 0 || _height <= 0) return;
    final inflated = [for (final (x, y, w, h) in _pending) (x - margin, y - margin, w + 2 * margin, h + 2 * margin)];
    _pending.clear();
    // 相交区域先合并（如先后到达的高亮行与菜单），合并后面积超过半屏时直接整屏
    final rects = DirtyMerge.merge(_mergeTouching(inflated), _width, _height) ?? [(0, 0, _width, _height)];
    _guarded = rects;
    _guardUntil = _clock.elapsedMilliseconds + guard.inMilliseconds;
    refresh(rects);
  }

  void dispose() => _timer?.cancel();

  /// 把相交或相邻的区域合并为外接矩形，直到互不相交（避免重叠部分重复请求）
  static List<(int, int, int, int)> _mergeTouching(List<(int, int, int, int)> rects) {
    final out = <(int, int, int, int)>[];
    for (var r in rects) {
      for (var i = 0; i < out.length;) {
        final o = out[i];
        final touch = r.$1 <= o.$1 + o.$3 && o.$1 <= r.$1 + r.$3 && r.$2 <= o.$2 + o.$4 && o.$2 <= r.$2 + r.$4;
        if (!touch) {
          i++;
          continue;
        }
        // 合并后移除原区域，从头再与其余区域比较
        final l = r.$1 < o.$1 ? r.$1 : o.$1, t = r.$2 < o.$2 ? r.$2 : o.$2;
        final rr = r.$1 + r.$3 > o.$1 + o.$3 ? r.$1 + r.$3 : o.$1 + o.$3;
        final b = r.$2 + r.$4 > o.$2 + o.$4 ? r.$2 + r.$4 : o.$2 + o.$4;
        r = (l, t, rr - l, b - t);
        out.removeAt(i);
        i = 0;
      }
      out.add(r);
    }
    return out;
  }

  /// [outer] 是否完整包含 [inner]
  static bool _contains((int, int, int, int) outer, (int, int, int, int) inner) =>
      inner.$1 >= outer.$1 &&
      inner.$2 >= outer.$2 &&
      inner.$1 + inner.$3 <= outer.$1 + outer.$3 &&
      inner.$2 + inner.$4 <= outer.$2 + outer.$4;
}
