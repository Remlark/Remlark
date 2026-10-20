import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:pointycastle/export.dart';
import 'package:remlark/modules/remote_desktop/remote_display.dart';
import 'package:remlark/modules/remote_desktop/vnc/ard_auth.dart';
import 'package:remlark/modules/remote_desktop/vnc/rfb_client.dart';
import 'package:remlark/utils/async_byte_reader.dart';
import 'package:remlark/utils/des.dart';

/// RFC 2409 Oakley 第 2 组 1024 位素数（与 macOS 屏幕共享使用的 DH 参数规模一致）
final _prime = BigInt.parse(
  'FFFFFFFFFFFFFFFFC90FDAA22168C234C4C6628B80DC1CD129024E088A67CC74020BBEA63B139B22514A08798E3404DD'
  'EF9519B3CD3A431B302B0A6DF25F14374FE1356D6D51C245E485B576625E7EC6F44C42E9A637ED6B0BFF5CB6F406B7ED'
  'EE386BFB5A899FA5AE9F24117C4B1FE649286651ECE65381FFFFFFFFFFFFFFFF',
  radix: 16,
);

Uint8List _bytes(BigInt v, int len) {
  final out = Uint8List(len);
  var x = v;
  for (var i = len - 1; i >= 0; i--) {
    out[i] = (x & BigInt.from(0xff)).toInt();
    x >>= 8;
  }
  return out;
}

BigInt _big(List<int> b) => b.fold(BigInt.zero, (r, e) => (r << 8) | BigInt.from(e));

/// 读取以 0 结尾的字段
String _cstr(Uint8List b, int off) => utf8.decode(b.sublist(off, b.indexOf(0, off)));

/// 模拟 macOS 屏幕共享：只提供 Apple 认证类型，服务端解密凭据并核对用户名与密码
Future<ServerSocket> _fakeArdServer(String user, String pass) async {
  final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
  server.listen((s) async {
    final r = AsyncByteReader(s);
    s.add('RFB 003.889\n'.codeUnits);
    await r.read(12);
    s.add([4, 30, 33, 36, 35]);
    // 客户端缺凭据时会直接断开
    final type = await r.u8().catchError((_) => -1);
    if (type != 30) return;
    const keyLen = 128;
    final priv = BigInt.parse('1234567890ABCDEF1234567890ABCDEF', radix: 16);
    final pub = BigInt.two.modPow(priv, _prime);
    s.add([0, 2, keyLen >> 8, keyLen & 0xff, ..._bytes(_prime, keyLen), ..._bytes(pub, keyLen)]);
    final cipher = await r.read(128);
    final clientPub = _big(await r.read(keyLen));
    final key = MD5Digest().process(_bytes(clientPub.modPow(priv, _prime), keyLen));
    final aes = AESEngine()..init(false, KeyParameter(key));
    final plain = Uint8List(128);
    for (var i = 0; i < 128; i += 16) {
      aes.processBlock(cipher, i, plain, i);
    }
    final ok = _cstr(plain, 0) == user && _cstr(plain, 64) == pass;
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
      ..setUint32(20, 3);
    s.add(init.buffer.asUint8List());
    s.add('mac'.codeUnits);
  });
  return server;
}

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
    // SetEncodings：头部 + 编码列表（含 Cursor 伪编码 -239）
    final encHead = await r.read(4);
    final encs = ByteData.sublistView(await r.read(((encHead[2] << 8) | encHead[3]) * 4));
    expect([for (var i = 0; i < encs.lengthInBytes; i += 4) encs.getInt32(i)], contains(-239));
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

  test('macOS 屏幕共享（Apple 认证）：缺用户名时要求输入，凭据正确连接成功，错误抛出认证异常', () async {
    final server = await _fakeArdServer('zhy2006', '密码pass');
    final c1 = RfbClient();
    await expectLater(
      c1.connect('127.0.0.1', server.port, password: 'x'),
      throwsA(isA<RfbPasswordRequired>().having((e) => e.needUsername, 'needUsername', isTrue)),
    );
    c1.close();

    final c2 = RfbClient();
    await c2.connect('127.0.0.1', server.port, username: 'zhy2006', password: '密码pass');
    expect(c2.securityType, ArdAuth.securityType);
    expect(c2.desktopName, 'mac');
    expect(c2.width, 4);
    c2.close();

    final c3 = RfbClient();
    await expectLater(
      c3.connect('127.0.0.1', server.port, username: 'zhy2006', password: 'wrong'),
      throwsA(isA<RfbAuthException>()),
    );
    c3.close();
    await server.close();
  });

  test('一次更新接收到一半时标记为 updating，完整后才触发 onFrame（避免撕裂）；指针伪编码', () async {
    final second = Completer<void>();
    final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((s) async {
      final r = AsyncByteReader(s);
      s.add('RFB 003.008\n'.codeUnits);
      await r.read(12);
      s.add([1, 1]); // 无认证
      await r.u8();
      s.add([0, 0, 0, 0]);
      await r.u8(); // ClientInit
      final init = ByteData(24)
        ..setUint16(0, 2)
        ..setUint16(2, 2)
        ..setUint32(20, 1);
      s.add([...init.buffer.asUint8List(), ...'t'.codeUnits]);
      // 更新包含两个 Raw 矩形：先只发第一行，等测试检查后再发第二行
      s.add([0, 0, 0, 2, ..._rect(0, 0, 2, 1, 0), ...List.filled(8, 0xFF)]);
      await second.future;
      s.add([..._rect(0, 1, 2, 1, 0), ...List.filled(8, 0xFF)]);
      // 指针形状：2×1，热点 (1,0)，掩码只有第一个像素不透明
      s.add([0, 0, 0, 1, ..._rect(1, 0, 2, 1, -239), 1, 2, 3, 0, 4, 5, 6, 0, 0x80]);
    });
    final c = RfbClient();
    var frames = 0;
    c.onFrame = () => frames++;
    RemoteCursor? cursor;
    c.onCursor = (cur) => cursor = cur;
    await c.connect('127.0.0.1', server.port);
    // 等第一行写入帧缓冲
    while (c.framebuffer[0] != 0xFF) {
      await Future.delayed(const Duration(milliseconds: 10));
    }
    expect(c.updating, isTrue);
    expect(frames, 0);
    second.complete();
    while (frames == 0) {
      await Future.delayed(const Duration(milliseconds: 10));
    }
    expect(c.updating, isFalse);
    expect(c.framebuffer.every((b) => b == 0xFF), isTrue);
    // 指针伪编码：本地绘制，不写入帧缓冲
    while (cursor == null) {
      await Future.delayed(const Duration(milliseconds: 10));
    }
    expect((cursor!.width, cursor!.height, cursor!.hotX, cursor!.hotY), (2, 1, 1, 0));
    expect(cursor!.bgra, [1, 2, 3, 255, 4, 5, 6, 0]);
    expect(c.framebuffer.every((b) => b == 0xFF), isTrue);
    c.close();
    await server.close();
  });

  test('连续到达的单矩形更新合并为一帧呈现（避免撕裂）', () async {
    final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    final later = Completer<void>();
    server.listen((s) async {
      final r = AsyncByteReader(s);
      s.add('RFB 003.008\n'.codeUnits);
      await r.read(12);
      s.add([1, 1]);
      await r.u8();
      s.add([0, 0, 0, 0]);
      await r.u8();
      final init = ByteData(24)
        ..setUint16(0, 3)
        ..setUint16(2, 1)
        ..setUint32(20, 1);
      s.add([...init.buffer.asUint8List(), ...'t'.codeUnits]);
      // 一次画面变化被拆成 3 个更新连续发送（与 macOS 行为一致）
      for (var x = 0; x < 3; x++) {
        s.add([0, 0, 0, 1, ..._rect(x, 0, 1, 1, 0), 0x11, 0x22, 0x33, 0]);
      }
      await later.future;
      s.add([0, 0, 0, 1, ..._rect(0, 0, 1, 1, 0), 0x44, 0x55, 0x66, 0]);
    });
    final c = RfbClient();
    final frames = <List<int>>[];
    c.onFrame = () => frames.add(List.of(c.framebuffer));
    await c.connect('127.0.0.1', server.port);
    await Future.delayed(const Duration(milliseconds: 100));
    expect(frames, hasLength(1), reason: '3 个连续更新应合并为 1 帧');
    expect(frames.single, [0x11, 0x22, 0x33, 255, 0x11, 0x22, 0x33, 255, 0x11, 0x22, 0x33, 255]);
    later.complete();
    await Future.delayed(const Duration(milliseconds: 100));
    expect(frames, hasLength(2));
    expect(frames.last.sublist(0, 4), [0x44, 0x55, 0x66, 255]);
    c.close();
    await server.close();
  });

  test('ContinuousUpdates：服务器支持时启用推送模式、不再逐次请求；回应服务器 Fence', () async {
    final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    final requests = <int>[];
    final enables = <List<int>>[];
    final fences = <List<int>>[];
    final push = Completer<void>();
    server.listen((s) async {
      final r = AsyncByteReader(s);
      s.add('RFB 003.008\n'.codeUnits);
      await r.read(12);
      s.add([1, 1]);
      await r.u8();
      s.add([0, 0, 0, 0]);
      await r.u8();
      final init = ByteData(24)
        ..setUint16(0, 2)
        ..setUint16(2, 1)
        ..setUint32(20, 1);
      s.add([...init.buffer.asUint8List(), ...'t'.codeUnits]);
      unawaited(() async {
        try {
          while (true) {
            final t = await r.u8();
            if (t == 0) await r.read(19);
            if (t == 2) {
              final h = await r.read(3);
              final encs = ByteData.sublistView(await r.read(((h[1] << 8) | h[2]) * 4));
              final list = [for (var i = 0; i < encs.lengthInBytes; i += 4) encs.getInt32(i)];
              if (list.contains(-313)) s.add([150]); // EndOfContinuousUpdates：声明支持
            }
            if (t == 3) requests.add((await r.read(9))[0]);
            if (t == 150) {
              enables.add(await r.read(9));
              if (!push.isCompleted) push.complete();
            }
            if (t == 248) {
              await r.read(3);
              final f = await r.read(4);
              fences.add([...f, ...await r.read(await r.u8())]);
            }
            if (t == 4) await r.read(7);
            if (t == 5) await r.read(5);
          }
        } catch (_) {}
      }());
      await push.future;
      // 推送模式：不等请求，连续推送 3 个更新
      for (var i = 0; i < 3; i++) {
        s.add([0, 0, 0, 1, ..._rect(0, 0, 1, 1, 0), i, i, i, 0]);
        await Future.delayed(const Duration(milliseconds: 80));
      }
      // 服务器 Fence（请求标志 + BlockBefore），负载 2 字节
      s.add([248, 0, 0, 0, 0x80, 0, 0, 0x01, 2, 7, 9]);
    });
    final c = RfbClient();
    var frames = 0;
    c.onFrame = () => frames++;
    await c.connect('127.0.0.1', server.port);
    for (var i = 0; i < 100 && (frames < 3 || fences.isEmpty); i++) {
      await Future.delayed(const Duration(milliseconds: 20));
    }
    expect(c.continuousUpdates, isTrue);
    expect(enables.single, [1, 0, 0, 0, 0, 0, 2, 0, 1], reason: '启用整屏 2×1');
    expect(frames, 3);
    expect(requests, [0], reason: '只有连接时的整屏请求，推送模式下不再逐次请求');
    expect(fences.single, [0, 0, 0, 0x01, 7, 9], reason: '回应时去掉请求标志并带回原负载');
    c.close();
    await server.close();
  });
}
