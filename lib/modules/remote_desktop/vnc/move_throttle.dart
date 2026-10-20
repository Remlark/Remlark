import 'dart:async';

/// 鼠标移动限流：每 [interval] 最多发送一次，只发送最新位置。
/// 本地鼠标事件可达每秒数百次，全部转发会在服务器端排队，导致光标、菜单、拖动明显滞后
class MoveThrottle {
  MoveThrottle(this._send, {this.interval = const Duration(milliseconds: 16)});

  final void Function(int x, int y) _send;
  final Duration interval;

  (int, int)? _pending;
  Timer? _timer;

  /// 记录一次移动：空闲时立即发送，否则合并到下一个周期
  void move(int x, int y) {
    _pending = (x, y);
    if (_timer?.isActive ?? false) return;
    flush();
    _timer = Timer.periodic(interval, (t) {
      if (_pending == null) {
        t.cancel();
        return;
      }
      flush();
    });
  }

  /// 立即发送尚未发送的移动（滚轮等需要先同步位置的操作前调用）
  void flush() {
    final m = _pending;
    if (m == null) return;
    _pending = null;
    _send(m.$1, m.$2);
  }

  /// 丢弃尚未发送的移动（按键状态变化时，新位置随按键一起发送）
  void drop() => _pending = null;

  void cancel() {
    _timer?.cancel();
    _pending = null;
  }
}
