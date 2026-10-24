import 'dart:async';

/// 按进入顺序执行异步操作；某个任务失败不会阻断后续任务。
class SerialExecutor {
  Future<void> _tail = Future.value();

  /// 将完整业务操作加入队列，并向调用方返回该任务自身的结果或异常。
  Future<T> run<T>(Future<T> Function() operation) {
    final result = _tail.then((_) => operation());
    _tail = result.then<void>(
      (_) {},
      onError: (Object error, StackTrace stack) {},
    );
    return result;
  }
}
