import 'dart:async';
import 'dart:io';

import '../../utils/network_endpoint.dart';
import '../hosts/host_model.dart';
import '../ssh/proxy_socket.dart';

/// 测试状态与错误种类；不直接把服务端响应或凭据显示在界面。
enum ProxyTestStatus {
  success,
  timeout,
  authentication,
  connection,
  protocol,
  cancelled,
  invalid,
}

/// 一次代理握手及目标连接的结果；耗时不代表真实业务延迟。
class ProxyTestResult {
  const ProxyTestResult(this.status, this.elapsed);
  final ProxyTestStatus status;
  final Duration elapsed;
}

/// 平台无关的连接检测接口，可由 UI 测试替换，不影响保存行为。
abstract interface class ProxyConnectionTest {
  /// 检测当前配置到指定目标的代理连接，不保存配置。
  Future<ProxyTestResult> check(ProxyConfig config, NetworkEndpoint target);
  /// 取消当前请求并释放连接资源。
  void cancel();
}

/// 三个桌面平台共用 Dart Socket 和现有 HTTP CONNECT / SOCKS5 实现。
class SocketProxyConnectionTest implements ProxyConnectionTest {
  SocketProxyConnectionTest({this.timeout = const Duration(seconds: 8)});
  final Duration timeout;
  Socket? _socket;
  int _generation = 0;

  /// 取消时销毁连接，并使稍后到达的旧连接和测试结果失效。
  @override
  void cancel() {
    _generation++;
    _socket?.destroy();
    _socket = null;
  }

  /// 实际验证代理握手、认证和连接目标；总体超时不随零碎响应延长。
  @override
  Future<ProxyTestResult> check(
    ProxyConfig config,
    NetworkEndpoint target,
  ) async {
    cancel();
    final generation = _generation;
    final watch = Stopwatch()..start();
    // 每个结果都检查请求代次，取消后的旧请求不能再返回成功。
    ProxyTestResult result(ProxyTestStatus status) => ProxyTestResult(
      generation == _generation ? status : ProxyTestStatus.cancelled,
      watch.elapsed,
    );
    if (!config.enabled ||
        config.port > 65535 ||
        target.port < 1 ||
        target.port > 65535 ||
        target.host.isEmpty) {
      return result(ProxyTestStatus.invalid);
    }
    try {
      final channel = await ProxyConnector.connect(
        target.host,
        target.port,
        config,
        timeout: timeout,
        onSocket: (socket) {
          if (generation != _generation) {
            socket.destroy();
          } else {
            _socket = socket;
          }
        },
      ).timeout(timeout);
      channel.destroy();
      return result(ProxyTestStatus.success);
    } on TimeoutException {
      return result(ProxyTestStatus.timeout);
    } on ProxyException catch (error) {
      return result(
        error.message.contains('auth') || error.message.contains('407')
            ? ProxyTestStatus.authentication
            : ProxyTestStatus.protocol,
      );
    } on SocketException {
      return result(ProxyTestStatus.connection);
    } catch (_) {
      return result(ProxyTestStatus.protocol);
    } finally {
      if (generation == _generation) {
        // 使超时后才完成 TCP 建连的回调也能销毁自己的资源。
        _socket?.destroy();
        _socket = null;
        _generation++;
      }
    }
  }
}
