import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dartssh2/dartssh2.dart';

import '../../utils/async_byte_reader.dart';
import '../hosts/host_model.dart';

/// 出口代理连接：支持 HTTP CONNECT 与 SOCKS5，返回可供 SSHClient 使用的 [SSHSocket]
class ProxyConnector {
  ProxyConnector._();

  /// 连接超时
  static const _timeout = Duration(seconds: 15);

  /// 打开到 [host]:[port] 的连接；[proxy] 未启用时直连
  static Future<SSHSocket> connect(String host, int port, ProxyConfig proxy) async {
    if (!proxy.enabled) {
      return SSHSocket.connect(host, port, timeout: _timeout);
    }
    final socket = await Socket.connect(proxy.host, proxy.port, timeout: _timeout);
    final reader = AsyncByteReader(socket);
    try {
      if (proxy.type == ProxyType.http) {
        await _httpConnect(socket, reader, host, port, proxy);
      } else {
        await _socks5Connect(socket, reader, host, port, proxy);
      }
    } catch (e) {
      socket.destroy();
      rethrow;
    }
    return _detach(socket, reader);
  }

  /// HTTP CONNECT 握手
  static Future<void> _httpConnect(
    Socket socket,
    AsyncByteReader reader,
    String host,
    int port,
    ProxyConfig proxy,
  ) async {
    final target = '$host:$port';
    final buf = StringBuffer()
      ..write('CONNECT $target HTTP/1.1\r\n')
      ..write('Host: $target\r\n');
    if (proxy.username.isNotEmpty) {
      final token = base64Encode(utf8.encode('${proxy.username}:${proxy.password ?? ''}'));
      buf.write('Proxy-Authorization: Basic $token\r\n');
    }
    buf.write('\r\n');
    socket.add(utf8.encode(buf.toString()));
    final header = await reader.readUntil(utf8.encode('\r\n\r\n'), timeout: _timeout);
    final statusLine = utf8.decode(header, allowMalformed: true).split('\r\n').first;
    final parts = statusLine.split(' ');
    if (parts.length < 2 || parts[1] != '200') {
      throw ProxyException('HTTP proxy: $statusLine');
    }
  }

  /// SOCKS5 握手（支持无认证与用户名密码认证）
  static Future<void> _socks5Connect(
    Socket socket,
    AsyncByteReader reader,
    String host,
    int port,
    ProxyConfig proxy,
  ) async {
    final useAuth = proxy.username.isNotEmpty;
    socket.add(useAuth ? [5, 2, 0, 2] : [5, 1, 0]);
    final method = await reader.read(2);
    if (method[0] != 5) throw ProxyException('SOCKS5: bad version');
    if (method[1] == 2) {
      final u = utf8.encode(proxy.username);
      final p = utf8.encode(proxy.password ?? '');
      socket.add([1, u.length, ...u, p.length, ...p]);
      final r = await reader.read(2);
      if (r[1] != 0) throw ProxyException('SOCKS5: authentication failed');
    } else if (method[1] != 0) {
      throw ProxyException('SOCKS5: no acceptable auth method');
    }
    final h = utf8.encode(host);
    socket.add([5, 1, 0, 3, h.length, ...h, (port >> 8) & 0xff, port & 0xff]);
    final head = await reader.read(4);
    if (head[1] != 0) throw ProxyException('SOCKS5: connect failed (code ${head[1]})');
    switch (head[3]) {
      case 1:
        await reader.read(4 + 2);
      case 3:
        final len = (await reader.read(1))[0];
        await reader.read(len + 2);
      case 4:
        await reader.read(16 + 2);
      default:
        throw ProxyException('SOCKS5: bad address type');
    }
  }
}

/// 代理握手异常
class ProxyException implements Exception {
  ProxyException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// 握手结束，接管剩余数据与后续数据，返回 SSHSocket
SSHSocket _detach(Socket socket, AsyncByteReader reader) {
  final controller = StreamController<Uint8List>();
  final (rest, sub) = reader.detach();
  if (rest.isNotEmpty) controller.add(rest);
  sub.onData(controller.add);
  sub.onError(controller.addError);
  sub.onDone(controller.close);
  if (reader.isClosed) controller.close();
  return _ProxiedSocket(socket, controller);
}

/// 经过代理握手后的 socket
class _ProxiedSocket implements SSHSocket {
  _ProxiedSocket(this._socket, this._controller);

  final Socket _socket;
  final StreamController<Uint8List> _controller;

  @override
  Stream<Uint8List> get stream => _controller.stream;

  @override
  StreamSink<List<int>> get sink => _socket;

  @override
  Future<void> get done => _socket.done;

  @override
  Future<void> close() async {
    await _socket.close();
  }

  @override
  void destroy() => _socket.destroy();

  @override
  Future<void> flush() => _socket.flush();
}
