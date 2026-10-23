import 'dart:async';
import 'dart:io';

import '../app_log.dart';
import 'connect_error_policy.dart';

/// TCP 建连的短暂不可达恢复；不包裹 SSH 认证或代理协议握手。
class ConnectRetry {
  ConnectRetry._();

  static const _delays = [Duration(milliseconds: 500), Duration(seconds: 1), Duration(seconds: 2)];

  /// 共用一个超时预算，最多建连四次；成功后立即返回，不增加正常连接延迟。
  /// 注入策略和等待函数用于确定性验证三平台行为。
  static Future<T> run<T>(
    Future<T> Function(Duration remaining) connect, {
    required Duration timeout,
    ConnectErrorPolicy? policy,
    Future<void> Function(Duration)? wait,
  }) async {
    final errors = policy ?? ConnectErrorPolicy.current();
    final pause = wait ?? Future<void>.delayed;
    final watch = Stopwatch()..start();
    for (var attempt = 0; ; attempt++) {
      final remaining = timeout - watch.elapsed;
      if (remaining <= Duration.zero) {
        throw TimeoutException('TCP connection timed out', timeout);
      }
      try {
        return await connect(remaining);
      } on SocketException catch (error) {
        if (!errors.isUnreachable(error) || attempt >= _delays.length) rethrow;
        final delay = _delays[attempt];
        // 不把单次超时重复累加；预算不足时保留最后一次系统错误。
        if (watch.elapsed + delay >= timeout) rethrow;
        AppLog.w(
          'network',
          'TCP 暂时不可达（errno=${error.osError?.errorCode}），'
              '${delay.inMilliseconds}ms 后重试 ${attempt + 1}/${_delays.length}',
        );
        await pause(delay);
      }
    }
  }
}
