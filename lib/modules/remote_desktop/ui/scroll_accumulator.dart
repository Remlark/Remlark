/// 把本地滚动位移（逻辑像素）折算为远程滚轮“格数”（参考 noVNC：每 [pixelsPerStep] 像素一格）。
///
/// - 触控板（[add]，细小连续位移）：累积到一格即发送 1 格并清零余数，每个事件最多 1 格，
///   发送节奏与本地事件同步，不积压、不丢弃
/// - 鼠标滚轮（[addWheel]）：一次真正的“一格”（位移不小于 [notchPixels]）至少滚 1 格，快速滚动按比例多滚，
///   单次上限 [maxWheelSteps]；高精度 / 平滑滚轮的细小位移先累积，满一格才发送（否则每个细小事件都会变成一格，
///   远程滚动过快且大量事件在服务器端排队）
class ScrollAccumulator {
  ScrollAccumulator({this.pixelsPerStep = 50, this.maxWheelSteps = 10, this.notchPixels = 30});

  /// 多少逻辑像素折算为一格（noVNC WHEEL_STEP）
  final double pixelsPerStep;

  /// 鼠标滚轮单个事件最多的格数
  final int maxWheelSteps;

  /// 位移不小于此值的滚轮事件视为一次完整的“一格”（如 macOS 普通滚轮每格约 40 像素）
  final double notchPixels;

  double _rest = 0;

  /// 触控板位移（正数向下）：返回 -1 / 0 / 1
  int add(double dy) {
    if (dy == 0) return 0;
    // 方向反转时丢弃上一方向的余数
    if (_rest != 0 && _rest.sign != dy.sign) _rest = 0;
    _rest += dy;
    if (_rest.abs() < pixelsPerStep) return 0;
    final step = _rest.sign.toInt();
    _rest = 0;
    return step;
  }

  /// 鼠标滚轮位移（正数向下）：返回格数（负数向上）
  int addWheel(double dy) {
    if (dy == 0) return 0;
    if (dy.abs() >= notchPixels) {
      // 完整的一格（或快速滚动的多格）
      _rest = 0;
      final steps = (dy.abs() / pixelsPerStep).round().clamp(1, maxWheelSteps);
      return dy < 0 ? -steps : steps;
    }
    // 平滑滚轮的细小位移：累积满一格才发送
    if (_rest != 0 && _rest.sign != dy.sign) _rest = 0;
    _rest += dy;
    final steps = (_rest / pixelsPerStep).truncate().clamp(-maxWheelSteps, maxWheelSteps);
    _rest -= steps * pixelsPerStep;
    return steps;
  }

  /// 清除余数（如触控板手势结束）
  void reset() => _rest = 0;
}
