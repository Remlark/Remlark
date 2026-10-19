import 'dart:async';
import 'dart:collection';
import 'dart:typed_data';

/// 异步字节读取器：从字节流中按需读取定长数据，适用于二进制协议解析
/// （VNC/RFB、代理握手等）。内部用块队列避免频繁拷贝。
class AsyncByteReader {
  AsyncByteReader(Stream<Uint8List> stream) {
    _sub = stream.listen(
      (data) {
        if (data.isEmpty) return;
        _chunks.add(data);
        _available += data.length;
        _wake();
      },
      onError: (Object e) {
        _error = e;
        _wake();
      },
      onDone: () {
        _closed = true;
        _wake();
      },
    );
  }

  late final StreamSubscription<Uint8List> _sub;
  final Queue<Uint8List> _chunks = Queue();
  int _offset = 0;
  int _available = 0;
  Completer<void>? _waiter;
  Object? _error;
  bool _closed = false;

  /// 当前缓冲的字节数
  int get available => _available;

  /// 流是否已结束
  bool get isClosed => _closed;

  void _wake() {
    final w = _waiter;
    _waiter = null;
    w?.complete();
  }

  Future<void> _waitFor(int n, Duration? timeout) async {
    while (_available < n) {
      if (_error != null) throw _error!;
      if (_closed) throw const SocketClosedException();
      _waiter = Completer<void>();
      final f = _waiter!.future;
      await (timeout == null ? f : f.timeout(timeout));
    }
  }

  /// 读取恰好 [n] 个字节
  Future<Uint8List> read(int n, {Duration? timeout}) async {
    if (n == 0) return Uint8List(0);
    await _waitFor(n, timeout);
    final out = Uint8List(n);
    var pos = 0;
    while (pos < n) {
      final head = _chunks.first;
      final take = (head.length - _offset).clamp(0, n - pos);
      out.setRange(pos, pos + take, head, _offset);
      pos += take;
      _offset += take;
      if (_offset >= head.length) {
        _chunks.removeFirst();
        _offset = 0;
      }
    }
    _available -= n;
    return out;
  }

  /// 读取无符号 8 位整数
  Future<int> u8() async => (await read(1))[0];

  /// 读取大端无符号 16 位整数
  Future<int> u16() async {
    final b = await read(2);
    return (b[0] << 8) | b[1];
  }

  /// 读取大端无符号 32 位整数
  Future<int> u32() async {
    final b = await read(4);
    return ByteData.sublistView(b).getUint32(0);
  }

  /// 读取大端有符号 32 位整数
  Future<int> s32() async {
    final b = await read(4);
    return ByteData.sublistView(b).getInt32(0);
  }

  /// 读取直到出现 [pattern]（包含 pattern），超过 [maxLength] 抛出异常
  Future<Uint8List> readUntil(List<int> pattern, {int maxLength = 64 * 1024, Duration? timeout}) async {
    final acc = BytesBuilder(copy: false);
    final window = <int>[];
    while (true) {
      final b = (await read(1, timeout: timeout))[0];
      acc.addByte(b);
      window.add(b);
      if (window.length > pattern.length) window.removeAt(0);
      if (window.length == pattern.length) {
        var match = true;
        for (var i = 0; i < pattern.length; i++) {
          if (window[i] != pattern[i]) {
            match = false;
            break;
          }
        }
        if (match) return acc.takeBytes();
      }
      if (acc.length > maxLength) throw const FormatException('data too long');
    }
  }

  /// 结束读取器：返回剩余缓冲数据与原始订阅，由调用方接管后续数据
  (Uint8List rest, StreamSubscription<Uint8List> sub) detach() {
    final rest = BytesBuilder(copy: false);
    var first = true;
    for (final c in _chunks) {
      rest.add(first ? c.sublist(_offset) : c);
      first = false;
    }
    _chunks.clear();
    _available = 0;
    return (rest.takeBytes(), _sub);
  }

  /// 取消底层订阅
  Future<void> cancel() => _sub.cancel();
}

/// 连接已关闭
class SocketClosedException implements Exception {
  const SocketClosedException();

  @override
  String toString() => 'connection closed';
}
