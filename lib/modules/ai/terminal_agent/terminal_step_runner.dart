import 'dart:async';

import '../../../utils/ansi_utils.dart';
import 'terminal_agent_protocol.dart';
import 'terminal_driver.dart';

/// 停止信号：用户点击停止时触发，正在进行的等待立即结束
class StopSignal {
  final _c = Completer<void>();

  bool get stopped => _c.isCompleted;
  Future<void> get future => _c.future;

  void stop() {
    if (!_c.isCompleted) _c.complete();
  }
}

/// 在终端中执行 Agent 的动作并收集输出。
///
/// 从任务开始到结束持续记录终端输出，每次汇报“上次汇报之后的新输出”，
/// 因此 Agent 思考期间命令产生的输出也不会丢失。命令是否结束由 Agent 判断，这里只按输出是否停顿决定何时汇报。
class TerminalStepRunner {
  TerminalStepRunner(this.driver, this.stop) {
    _sub = driver.output.listen(_onOutput);
  }

  final TerminalDriver driver;
  final StopSignal stop;
  late final StreamSubscription<String> _sub;

  /// 上次汇报之后的原始输出
  final _pending = StringBuffer();
  DateTime _lastOutput = DateTime.now();
  bool _gotOutput = false;

  /// 原始输出缓存上限（超过时丢弃开头，汇报只保留末尾）
  static const _maxRaw = 2 << 20;

  /// 执行命令后：输出停顿这么久就汇报（测试时可缩短）
  static Duration runIdle = const Duration(seconds: 2);

  /// 执行命令后最长等待（输出持续不断时先汇报一次，由 Agent 决定是否继续等）
  static Duration runMax = const Duration(seconds: 20);

  /// wait 期间：有新输出后又停顿这么久就提前汇报（命令可能已结束）
  static Duration waitIdle = const Duration(seconds: 5);

  /// 汇报前至少等待的时间（测试时可缩短）
  static Duration minCollect = const Duration(milliseconds: 800);

  void _onOutput(String data) {
    _pending.write(data);
    if (_pending.length > _maxRaw) {
      final s = _pending.toString();
      _pending
        ..clear()
        ..write(s.substring(s.length - _maxRaw ~/ 2));
    }
    _lastOutput = DateTime.now();
    _gotOutput = true;
  }

  /// 执行命令：[autoSubmit] 为 false 时填入终端并等待用户按回车（期间 [onWaitingEnter] 为 true）。
  /// 返回交给 Agent 的输出；命令未执行（停止、用户按 Ctrl+C、连接断开）返回 null
  Future<String?> run(String command, {required bool autoSubmit, void Function(bool waiting)? onWaitingEnter}) async {
    if (!driver.connected) return null;
    _take(); // 丢弃输入命令之前的输出（提问时已附上屏幕内容）
    driver.type(command, submit: autoSubmit);
    if (!autoSubmit) {
      onWaitingEnter?.call(true);
      final ok = await _waitForEnter();
      onWaitingEnter?.call(false);
      if (!ok) return null;
    }
    await _collect(max: runMax, idle: runIdle);
    return stop.stopped ? null : _report();
  }

  /// 等待 [seconds] 秒（有新输出后停顿 [waitIdle] 则提前），返回期间的新输出
  Future<String?> wait(int seconds) async {
    await _collect(max: Duration(seconds: seconds), idle: waitIdle, requireNew: true);
    return stop.stopped ? null : _report();
  }

  /// 等待用户在终端按回车（执行）或 Ctrl+C（放弃）
  Future<bool> _waitForEnter() async {
    final done = Completer<bool>();
    final sub = driver.userInput.listen((s) {
      if (done.isCompleted) return;
      if (s.contains('\x03')) {
        done.complete(false);
      } else if (s.contains('\r') || s.contains('\n')) {
        done.complete(true);
      }
    });
    final r = await Future.any([done.future, stop.future.then((_) => false)]);
    await sub.cancel();
    return r && !stop.stopped;
  }

  /// 等待输出：超过 [max]，或（已有新输出且）停顿超过 [idle] 时返回；停止或断开时立即返回
  Future<void> _collect({required Duration max, required Duration idle, bool requireNew = false}) async {
    final start = DateTime.now();
    if (requireNew) _gotOutput = false;
    while (!stop.stopped && driver.connected) {
      final now = DateTime.now();
      if (now.difference(start) >= max) return;
      final quiet = now.difference(_lastOutput) >= idle;
      if (quiet && (_gotOutput || !requireNew) && now.difference(start) >= minCollect) return;
      await Future.any([Future<void>.delayed(const Duration(milliseconds: 50)), stop.future]);
    }
  }

  /// 取出上次汇报后的原始输出
  String _take() {
    final s = _pending.toString();
    _pending.clear();
    _gotOutput = false;
    return s;
  }

  /// 汇报：转纯文本并只保留末尾
  String _report() => AnsiUtils.tail(AnsiUtils.toPlainText(_take()), TerminalAgentProtocol.maxOutput);

  /// 结束记录
  Future<void> dispose() => _sub.cancel();
}
