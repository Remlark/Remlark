import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import '../../../utils/async_byte_reader.dart';
import '../../../utils/des.dart';

/// VNC 认证失败
class RfbAuthException implements Exception {
  RfbAuthException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// 需要密码但未提供
class RfbPasswordRequired implements Exception {}

/// RFB（VNC）协议客户端：实现 3.3/3.7/3.8 握手、None 与 VNC 认证、
/// Raw / CopyRect / ZRLE 编码、DesktopSize 伪编码、键鼠事件与剪贴板。
/// 帧缓冲格式为 BGRA8888，可直接交给 Flutter 绘制。
class RfbClient {
  RfbClient();

  Socket? _socket;
  AsyncByteReader? _reader;

  /// 远程桌面宽高与名称
  int width = 0;
  int height = 0;
  String desktopName = '';

  /// 帧缓冲（BGRA）
  Uint8List framebuffer = Uint8List(0);

  /// 帧缓冲更新回调（一次 FramebufferUpdate 完成后触发）
  void Function()? onFrame;

  /// 远程尺寸变化回调
  void Function(int w, int h)? onResize;

  /// 远程剪贴板文本回调
  void Function(String text)? onClipboard;

  /// 连接关闭回调
  void Function(Object? error)? onClosed;

  /// 响铃回调
  void Function()? onBell;

  RawZLibFilter? _zlib;
  bool _closed = false;

  static const _encRaw = 0;
  static const _encCopyRect = 1;
  static const _encZrle = 16;
  static const _encDesktopSize = -223;

  /// 连接并完成握手；[password] 为空且服务器要求认证时抛出 [RfbPasswordRequired]
  Future<void> connect(String host, int port, {String? password}) async {
    final socket = await Socket.connect(host, port, timeout: const Duration(seconds: 15));
    socket.setOption(SocketOption.tcpNoDelay, true);
    _socket = socket;
    final r = AsyncByteReader(socket);
    _reader = r;
    const t = Duration(seconds: 20);

    // 1. 协议版本
    final ver = ascii.decode(await r.read(12, timeout: t));
    final m = RegExp(r'RFB (\d{3})\.(\d{3})').firstMatch(ver);
    if (m == null) throw const FormatException('not a VNC server');
    final minor = int.parse(m.group(2)!);
    final useMinor = minor >= 8 ? 8 : (minor >= 7 ? 7 : 3);
    socket.add(ascii.encode('RFB 003.00$useMinor\n'));

    // 2. 安全类型协商
    int secType;
    if (useMinor == 3) {
      secType = await r.u32();
      if (secType == 0) throw RfbAuthException(await _readReason());
    } else {
      final n = await r.u8();
      if (n == 0) throw RfbAuthException(await _readReason());
      final types = await r.read(n, timeout: t);
      if (types.contains(2) && (password?.isNotEmpty ?? false)) {
        secType = 2;
      } else if (types.contains(1)) {
        secType = 1;
      } else if (types.contains(2)) {
        secType = 2;
      } else {
        throw RfbAuthException('unsupported security types: $types');
      }
      socket.add([secType]);
    }

    // 3. 认证
    if (secType == 2) {
      if (password == null || password.isEmpty) {
        throw RfbPasswordRequired();
      }
      final challenge = await r.read(16, timeout: t);
      socket.add(Des.vncResponse(password, challenge));
    }
    if (secType == 2 || useMinor == 8) {
      final result = await r.u32();
      if (result != 0) {
        final reason = useMinor == 8 ? await _readReason() : 'authentication failed';
        throw RfbAuthException(reason);
      }
    }

    // 4. ClientInit（共享桌面）/ ServerInit
    socket.add([1]);
    width = await r.u16();
    height = await r.u16();
    await r.read(16); // 服务器像素格式，下面会强制设置为我们需要的格式
    final nameLen = await r.u32();
    desktopName = utf8.decode(await r.read(nameLen), allowMalformed: true);
    framebuffer = Uint8List(width * height * 4);

    _setPixelFormat();
    _setEncodings();
    requestUpdate(incremental: false);
    unawaited(_loop());
  }

  Future<String> _readReason() async {
    final len = await _reader!.u32();
    return utf8.decode(await _reader!.read(len), allowMalformed: true);
  }

  /// 设置像素格式：32bpp、深度 24、小端、真彩色，R/G/B 位移 16/8/0（内存顺序 BGRX）
  void _setPixelFormat() {
    final b = ByteData(20);
    b.setUint8(0, 0);
    b.setUint8(4, 32); // bits-per-pixel
    b.setUint8(5, 24); // depth
    b.setUint8(6, 0); // big-endian flag
    b.setUint8(7, 1); // true-colour
    b.setUint16(8, 255);
    b.setUint16(10, 255);
    b.setUint16(12, 255);
    b.setUint8(14, 16);
    b.setUint8(15, 8);
    b.setUint8(16, 0);
    _socket!.add(b.buffer.asUint8List());
  }

  /// 声明支持的编码（优先 ZRLE）
  void _setEncodings() {
    const encs = [_encZrle, _encCopyRect, _encRaw, _encDesktopSize];
    final b = ByteData(4 + encs.length * 4);
    b.setUint8(0, 2);
    b.setUint16(2, encs.length);
    for (var i = 0; i < encs.length; i++) {
      b.setInt32(4 + i * 4, encs[i]);
    }
    _socket!.add(b.buffer.asUint8List());
  }

  /// 请求帧缓冲更新
  void requestUpdate({bool incremental = true}) {
    if (_closed || _socket == null) return;
    final b = ByteData(10);
    b.setUint8(0, 3);
    b.setUint8(1, incremental ? 1 : 0);
    b.setUint16(6, width);
    b.setUint16(8, height);
    _socket!.add(b.buffer.asUint8List());
  }

  /// 发送键盘事件（X11 keysym）
  void sendKey(int keysym, bool down) {
    if (_closed) return;
    final b = ByteData(8);
    b.setUint8(0, 4);
    b.setUint8(1, down ? 1 : 0);
    b.setUint32(4, keysym);
    _socket?.add(b.buffer.asUint8List());
  }

  /// 发送鼠标事件；[buttons] 位掩码：1 左键、2 中键、4 右键、8 滚轮上、16 滚轮下
  void sendPointer(int x, int y, int buttons) {
    if (_closed) return;
    final b = ByteData(6);
    b.setUint8(0, 5);
    b.setUint8(1, buttons);
    b.setUint16(2, x.clamp(0, width > 0 ? width - 1 : 0));
    b.setUint16(4, y.clamp(0, height > 0 ? height - 1 : 0));
    _socket?.add(b.buffer.asUint8List());
  }

  /// 发送剪贴板文本到远程（RFB 规定为 Latin-1，无法表示的字符替换为 ?）
  void sendClipboard(String text) {
    if (_closed) return;
    final bytes = Uint8List.fromList(text.codeUnits.map((c) => c < 256 ? c : 0x3f).toList());
    final b = ByteData(8);
    b.setUint8(0, 6);
    b.setUint32(4, bytes.length);
    _socket?.add(b.buffer.asUint8List());
    _socket?.add(bytes);
  }

  /// 主消息循环
  Future<void> _loop() async {
    final r = _reader!;
    Object? error;
    try {
      while (!_closed) {
        final type = await r.u8();
        switch (type) {
          case 0:
            await _readFramebufferUpdate();
            onFrame?.call();
            requestUpdate();
          case 1:
            await r.read(1);
            await r.u16();
            final n = await r.u16();
            await r.read(n * 6);
          case 2:
            onBell?.call();
          case 3:
            await r.read(3);
            final len = await r.s32();
            if (len < 0) {
              // 扩展剪贴板格式，暂不支持，跳过
              await r.read(-len);
            } else {
              final data = await r.read(len);
              onClipboard?.call(_decodeClipboard(data));
            }
          default:
            throw FormatException('unknown server message $type');
        }
      }
    } catch (e) {
      if (!_closed) error = e;
    }
    _closed = true;
    _socket?.destroy();
    onClosed?.call(error);
  }

  /// 剪贴板：优先按 UTF-8 解码（很多服务器实际发送 UTF-8），失败按 Latin-1
  static String _decodeClipboard(Uint8List data) {
    try {
      return utf8.decode(data);
    } catch (_) {
      return latin1.decode(data);
    }
  }

  Future<void> _readFramebufferUpdate() async {
    final r = _reader!;
    await r.read(1);
    final n = await r.u16();
    for (var i = 0; i < n; i++) {
      final x = await r.u16();
      final y = await r.u16();
      final w = await r.u16();
      final h = await r.u16();
      final enc = await r.s32();
      switch (enc) {
        case _encRaw:
          await _readRaw(x, y, w, h);
        case _encCopyRect:
          final sx = await r.u16();
          final sy = await r.u16();
          _copyRect(sx, sy, x, y, w, h);
        case _encZrle:
          await _readZrle(x, y, w, h);
        case _encDesktopSize:
          _resize(w, h);
        default:
          throw FormatException('unsupported encoding $enc');
      }
    }
  }

  void _resize(int w, int h) {
    width = w;
    height = h;
    framebuffer = Uint8List(w * h * 4);
    onResize?.call(w, h);
  }

  Future<void> _readRaw(int x, int y, int w, int h) async {
    final data = await _reader!.read(w * h * 4);
    for (var row = 0; row < h; row++) {
      final dst = ((y + row) * width + x) * 4;
      final src = row * w * 4;
      framebuffer.setRange(dst, dst + w * 4, data, src);
      for (var c = 0; c < w; c++) {
        framebuffer[dst + c * 4 + 3] = 255;
      }
    }
  }

  void _copyRect(int sx, int sy, int dx, int dy, int w, int h) {
    final tmp = Uint8List(w * h * 4);
    for (var row = 0; row < h; row++) {
      final s = ((sy + row) * width + sx) * 4;
      tmp.setRange(row * w * 4, (row + 1) * w * 4, framebuffer, s);
    }
    for (var row = 0; row < h; row++) {
      final d = ((dy + row) * width + dx) * 4;
      framebuffer.setRange(d, d + w * 4, tmp, row * w * 4);
    }
  }

  /// ZRLE：zlib 流在整个连接中连续，按 64x64 瓦片解析
  Future<void> _readZrle(int x, int y, int w, int h) async {
    final len = await _reader!.u32();
    final compressed = await _reader!.read(len);
    final z = _zlib ??= RawZLibFilter.inflateFilter();
    z.process(compressed, 0, compressed.length);
    final out = BytesBuilder(copy: false);
    while (true) {
      final chunk = z.processed(flush: true);
      if (chunk == null || chunk.isEmpty) break;
      out.add(chunk);
    }
    final data = out.takeBytes();
    var pos = 0;

    // 读取一个 CPIXEL（3 字节：B G R）并写入帧缓冲
    for (var ty = y; ty < y + h; ty += 64) {
      final th = (y + h - ty) < 64 ? (y + h - ty) : 64;
      for (var tx = x; tx < x + w; tx += 64) {
        final tw = (x + w - tx) < 64 ? (x + w - tx) : 64;
        final sub = data[pos++];
        if (sub == 0) {
          for (var j = 0; j < th; j++) {
            for (var i = 0; i < tw; i++) {
              _put(tx + i, ty + j, data, pos);
              pos += 3;
            }
          }
        } else if (sub == 1) {
          final cp = pos;
          pos += 3;
          for (var j = 0; j < th; j++) {
            for (var i = 0; i < tw; i++) {
              _put(tx + i, ty + j, data, cp);
            }
          }
        } else if (sub >= 2 && sub <= 16) {
          final palette = pos;
          pos += sub * 3;
          final bits = sub == 2 ? 1 : (sub <= 4 ? 2 : 4);
          final mask = (1 << bits) - 1;
          for (var j = 0; j < th; j++) {
            var shift = 8 - bits;
            var byte = data[pos];
            for (var i = 0; i < tw; i++) {
              final idx = (byte >> shift) & mask;
              _put(tx + i, ty + j, data, palette + idx * 3);
              shift -= bits;
              if (shift < 0 && i < tw - 1) {
                shift = 8 - bits;
                byte = data[++pos];
              }
            }
            pos++;
          }
        } else if (sub == 128) {
          var i = 0;
          final total = tw * th;
          while (i < total) {
            final cp = pos;
            pos += 3;
            var run = 1;
            int b;
            do {
              b = data[pos++];
              run += b;
            } while (b == 255);
            for (var k = 0; k < run && i < total; k++, i++) {
              _put(tx + i % tw, ty + i ~/ tw, data, cp);
            }
          }
        } else if (sub >= 130) {
          final palette = pos;
          pos += (sub - 128) * 3;
          var i = 0;
          final total = tw * th;
          while (i < total) {
            var idx = data[pos++];
            var run = 1;
            if (idx & 128 != 0) {
              idx &= 127;
              int b;
              do {
                b = data[pos++];
                run += b;
              } while (b == 255);
            }
            for (var k = 0; k < run && i < total; k++, i++) {
              _put(tx + i % tw, ty + i ~/ tw, data, palette + idx * 3);
            }
          }
        } else {
          throw FormatException('bad ZRLE subencoding $sub');
        }
      }
    }
  }

  /// 写入一个像素（CPIXEL 为 B G R）
  void _put(int px, int py, Uint8List src, int off) {
    final d = (py * width + px) * 4;
    framebuffer[d] = src[off];
    framebuffer[d + 1] = src[off + 1];
    framebuffer[d + 2] = src[off + 2];
    framebuffer[d + 3] = 255;
  }

  /// 断开连接
  void close() {
    if (_closed) return;
    _closed = true;
    _socket?.destroy();
  }
}
