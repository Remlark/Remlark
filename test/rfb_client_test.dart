import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:remlark/modules/remote_desktop/vnc/rfb_client.dart';
import 'package:remlark/utils/async_byte_reader.dart';
import 'package:remlark/utils/des.dart';

/// 简易 RFB 服务端：VNC 认证 + 发送一个 Raw 矩形和一个 ZRLE 实色瓦片 + 剪贴板
Future<ServerSocket> _fakeServer(String password, Completer<String> clientCut) async {
  final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
  server.listen((s) async {
    final r = AsyncByteReader(s);
    s.add('RFB 003.008\n'.codeUnits);
    await r.read(12);
    s.add([1, 2]); // 一种安全类型：VNC 认证
    await r.u8();
    final challenge = List<int>.generate(16, (i) => i * 7);
    s.add(challenge);
    final resp = await r.read(16);
    final ok = _eq(resp, Des.vncResponse(password, challenge));
    s.add([0, 0, 0, ok ? 0 : 1]);
    if (!ok) {
      s.add([0, 0, 0, 4, ...'fail'.codeUnits]);
      await s.close();
      return;
    }
    await r.u8(); // ClientInit
    final init = ByteData(24)
      ..setUint16(0, 4)
      ..setUint16(2, 2)
      ..setUint32(20, 4);
    s.add(init.buffer.asUint8List());
    s.add('test'.codeUnits);
    await r.read(20); // SetPixelFormat
    await r.read(4 + 16); // SetEncodings：头部 + 4 个编码
    await r.read(10); // FramebufferUpdateRequest

    // FramebufferUpdate：Raw 2x1 在 (0,0)，ZRLE 实色 2x2 在 (2,0)
    final b = BytesBuilder();
    b.add([0, 0, 0, 2]);
    b.add(_rect(0, 0, 2, 1, 0));
    b.add([0x10, 0x20, 0x30, 0, 0x40, 0x50, 0x60, 0]);
    final zlib = ZLibCodec().encode([1, 0xAA, 0xBB, 0xCC]); // solid tile, CPIXEL = B G R
    b.add(_rect(2, 0, 2, 2, 16));
    final len = ByteData(4)..setUint32(0, zlib.length);
    b.add(len.buffer.asUint8List());
    b.add(zlib);
    // ServerCutText
    b.add([3, 0, 0, 0, 0, 0, 0, 5, ...'hello'.codeUnits]);
    s.add(b.toBytes());
    // 等待客户端剪贴板
    while (true) {
      final t = await r.u8();
      if (t == 3) {
        await r.read(9);
      } else if (t == 6) {
        await r.read(3);
        final l = await r.u32();
        clientCut.complete(String.fromCharCodes(await r.read(l)));
        break;
      } else if (t == 4) {
        await r.read(7);
      } else if (t == 5) {
        await r.read(5);
      }
    }
  });
  return server;
}

List<int> _rect(int x, int y, int w, int h, int enc) {
  final d = ByteData(12)
    ..setUint16(0, x)
    ..setUint16(2, y)
    ..setUint16(4, w)
    ..setUint16(6, h)
    ..setInt32(8, enc);
  return d.buffer.asUint8List();
}

bool _eq(List<int> a, List<int> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

void main() {
  test('RFB 握手、VNC 认证、Raw / ZRLE 解码与剪贴板', () async {
    final cut = Completer<String>();
    final server = await _fakeServer('secret', cut);
    final c = RfbClient();
    final frame = Completer<void>();
    final clip = Completer<String>();
    c.onFrame = () {
      if (!frame.isCompleted) frame.complete();
    };
    c.onClipboard = clip.complete;
    await c.connect('127.0.0.1', server.port, password: 'secret');
    expect(c.width, 4);
    expect(c.desktopName, 'test');
    await frame.future.timeout(const Duration(seconds: 5));
    final fb = c.framebuffer;
    expect(fb.sublist(0, 4), [0x10, 0x20, 0x30, 255]);
    expect(fb.sublist(4, 8), [0x40, 0x50, 0x60, 255]);
    // ZRLE 实色瓦片覆盖 (2..3, 0..1)
    expect(fb.sublist(8, 12), [0xAA, 0xBB, 0xCC, 255]);
    expect(fb.sublist((1 * 4 + 3) * 4, (1 * 4 + 3) * 4 + 4), [0xAA, 0xBB, 0xCC, 255]);
    expect(await clip.future.timeout(const Duration(seconds: 5)), 'hello');
    c.sendClipboard('from client');
    expect(await cut.future.timeout(const Duration(seconds: 5)), 'from client');
    c.close();
    await server.close();
  });

  test('VNC 密码错误抛出认证异常', () async {
    final server = await _fakeServer('secret', Completer());
    final c = RfbClient();
    await expectLater(c.connect('127.0.0.1', server.port, password: 'wrong'), throwsA(isA<RfbAuthException>()));
    await server.close();
  });
}
