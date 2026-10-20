import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:remlark/modules/remote_desktop/remote_display.dart';
import 'package:remlark/modules/remote_desktop/vnc/rfb_client.dart';
import 'package:remlark/modules/remote_desktop/vnc/rfb_isolate_client.dart';
import 'package:remlark/utils/async_byte_reader.dart';

List<int> _rect(int x, int y, int w, int h, int enc) {
  final d = ByteData(12)
    ..setUint16(0, x)
    ..setUint16(2, y)
    ..setUint16(4, w)
    ..setUint16(6, h)
    ..setInt32(8, enc);
  return d.buffer.asUint8List();
}

/// 模拟服务端：无认证，4×2 画面；收到客户端第 [n] 次信号后按脚本发送更新，记录客户端发来的鼠标事件
Future<(ServerSocket, StreamController<int>, List<List<int>>)> _server({bool failAuth = false}) async {
  final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
  final steps = StreamController<int>();
  final pointers = <List<int>>[];
  server.listen((s) async {
    final r = AsyncByteReader(s);
    s.add('RFB 003.008\n'.codeUnits);
    await r.read(12);
    if (failAuth) {
      s.add([1, 2]); // 只提供 VNC 密码认证
      await r.u8();
      s.add(List.filled(16, 1));
      await r.read(16);
      s.add([0, 0, 0, 1, 0, 0, 0, 3, ...'bad'.codeUnits]);
      return;
    }
    s.add([1, 1]);
    await r.u8();
    s.add([0, 0, 0, 0]);
    await r.u8();
    final init = ByteData(24)
      ..setUint16(0, 4)
      ..setUint16(2, 2)
      ..setUint32(20, 1);
    s.add([...init.buffer.asUint8List(), ...'t'.codeUnits]);
    // 首次整屏：红色
    s.add([0, 0, 0, 1, ..._rect(0, 0, 4, 2, 0), for (var i = 0; i < 8; i++) ...[0, 0, 255, 0]]);
    // 后台读取客户端消息（记录鼠标事件）
    unawaited(() async {
      try {
        while (true) {
          final t = await r.u8();
          if (t == 0) await r.read(19);
          if (t == 2) {
            final h = await r.read(3);
            await r.read(((h[1] << 8) | h[2]) * 4);
          }
          if (t == 3) await r.read(9);
          if (t == 4) await r.read(7);
          if (t == 5) pointers.add(await r.read(5));
          if (t == 6) {
            await r.read(3);
            await r.read(await r.u32());
          }
        }
      } catch (_) {}
    }());
    await for (final step in steps.stream) {
      // 每步发送一个 1×1 绿色更新在 (step, 0)
      s.add([0, 0, 0, 1, ..._rect(step, 0, 1, 1, 0), 0, 255, 0, 0]);
    }
  });
  return (server, steps, pointers);
}

Future<void> _until(bool Function() cond) async {
  for (var i = 0; i < 200 && !cond(); i++) {
    await Future.delayed(const Duration(milliseconds: 10));
  }
}

void main() {
  test('后台 isolate：首帧整屏、之后只传变化区域；UI 未取帧时后台合并（背压）；输入经后台发送', () async {
    final (server, steps, pointers) = await _server();
    final c = RfbIsolateClient();
    var notified = 0;
    c.onFrame = () => notified++;
    await c.connect('127.0.0.1', server.port);
    expect((c.width, c.height, c.desktopName), (4, 2, 't'));

    await _until(() => notified > 0);
    final first = c.takeFrame()!;
    expect(first.full, isTrue);
    expect(first.patches.single.bgra.sublist(0, 4), [0, 0, 255, 255]);

    // 发 1 个更新，取走；再连发 3 个更新但先不取（第 1 个在途，后 2 个应在后台合并）
    steps.add(0);
    await _until(() => notified > 1);
    final second = c.takeFrame()!;
    expect(second.full, isFalse);
    expect((second.patches.single.x, second.patches.single.w), (0, 1));
    expect(second.patches.single.bgra, [0, 255, 0, 255]);

    // 间隔发送 3 个更新（超过客户端 50ms 合并上限），期间不取帧：
    // 第 1 个在途，后 2 个应在后台累积，回执后作为 1 帧送达
    final before = notified;
    for (final x in [1, 2, 3]) {
      steps.add(x);
      await Future.delayed(const Duration(milliseconds: 100));
    }
    expect(notified - before, 1, reason: '未回执前只会收到 1 帧，其余在后台累积');
    final third = c.takeFrame()!;
    expect(third.patches.map((p) => p.x), [1]);
    await _until(() => notified - before >= 2);
    final fourth = c.takeFrame()!;
    expect(fourth.patches.map((p) => p.x).toSet(), {2, 3}, reason: '回执后发送累积的变化');

    c.sendPointer(3, 1, 1, input: true);
    await _until(() => pointers.isNotEmpty);
    expect(pointers.single, [1, 0, 3, 0, 1]);

    c.close();
    unawaited(steps.close());
    await server.close();
  });

  test('后台 isolate：认证失败映射为 RfbAuthException', () async {
    final (server, steps, _) = await _server(failAuth: true);
    final c = RfbIsolateClient();
    await expectLater(c.connect('127.0.0.1', server.port, password: 'x'), throwsA(isA<RfbAuthException>()));
    expect(c.securityType, 2);
    unawaited(steps.close());
    await server.close();
  });

  test('用户输入停止后自动整屏校验：后台发现增量遗漏并以整屏修复', () async {
    final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    var fullRequests = 0;
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
      try {
        while (true) {
          final t = await r.u8();
          if (t == 0) await r.read(19);
          if (t == 2) {
            final h = await r.read(3);
            await r.read(((h[1] << 8) | h[2]) * 4);
          }
          if (t == 4) await r.read(7);
          if (t == 5) await r.read(5);
          if (t == 3) {
            final req = await r.read(9);
            if (req[0] == 0) {
              fullRequests++;
              // 第 1 次为连接时的整屏（黑）；之后的整屏校验：第 2 个像素与增量结果不同（模拟遗漏的变化）
              final px = fullRequests == 1 ? [0, 0, 0, 0, 0, 0, 0, 0] : [0, 0, 0, 0, 9, 9, 9, 0];
              s.add([0, 0, 0, 1, ..._rect(0, 0, 2, 1, 0), ...px]);
            } else if (fullRequests == 1) {
              // 一次增量更新，产生“活动”触发之后的空闲校验
              fullRequests++;
              s.add([0, 0, 0, 1, ..._rect(0, 0, 1, 1, 0), 0, 0, 0, 0]);
            }
          }
        }
      } catch (_) {}
    });
    final c = RfbIsolateClient();
    final frames = <FrameUpdate>[];
    c.onFrame = () {
      final f = c.takeFrame();
      if (f != null) frames.add(f);
    };
    await c.connect('127.0.0.1', server.port);
    // 只有用户输入算活动：移动一下鼠标，停止后触发校验
    await Future.delayed(const Duration(milliseconds: 200));
    c.sendPointer(0, 0, 0);
    bool healed() => frames.any((f) => f.patches.any((p) => p.bgra.length >= 8 && p.bgra[4] == 9));
    await _until(healed);
    expect(healed(), isTrue, reason: '整屏校验结果送达界面，修复遗漏');
    c.close();
    await server.close();
  });

  test('点击后对指针附近补两次完整画面请求（约 120ms 与 400ms）', () async {
    final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    final regions = <(int, List<int>)>[];
    final clock = Stopwatch();
    server.listen((s) async {
      final r = AsyncByteReader(s);
      s.add('RFB 003.008\n'.codeUnits);
      await r.read(12);
      s.add([1, 1]);
      await r.u8();
      s.add([0, 0, 0, 0]);
      await r.u8();
      final init = ByteData(24)
        ..setUint16(0, 1920)
        ..setUint16(2, 1080)
        ..setUint32(20, 1);
      s.add([...init.buffer.asUint8List(), ...'t'.codeUnits]);
      try {
        while (true) {
          final t = await r.u8();
          if (t == 0) await r.read(19);
          if (t == 2) {
            final h = await r.read(3);
            await r.read(((h[1] << 8) | h[2]) * 4);
          }
          if (t == 3) {
            final q = ByteData.sublistView(await r.read(9));
            final region = [q.getUint8(0), q.getUint16(1), q.getUint16(3), q.getUint16(5), q.getUint16(7)];
            // 非增量且不是整屏：点击后的区域补刷新
            if (region[0] == 0 && region[3] != 1920) regions.add((clock.elapsedMilliseconds, region));
          }
          if (t == 4) await r.read(7);
          if (t == 5) await r.read(5);
          if (t == 6) {
            await r.read(3);
            await r.read(await r.u32());
          }
        }
      } catch (_) {}
    });
    final c = RfbIsolateClient();
    await c.connect('127.0.0.1', server.port);
    clock.start();
    c.sendPointer(600, 500, 4, input: true); // 右键按下
    await Future.delayed(const Duration(milliseconds: 700));
    expect(regions, hasLength(2));
    expect(regions[0].$1, inInclusiveRange(80, 300));
    expect(regions[1].$1, inInclusiveRange(350, 650));
    // 区域：以 (600,500) 为中心偏右下的 1000×1000
    expect(regions[0].$2.sublist(1), [350, 250, 1000, 830]);

    // 在远处再次点击（关闭旧菜单）：同时补刷新当前位置与上一次点击位置（旧菜单所在）
    regions.clear();
    c.sendPointer(1700, 100, 1, input: true);
    await Future.delayed(const Duration(milliseconds: 700));
    final spots = regions.map((r) => (r.$2[1], r.$2[2])).toSet();
    expect(spots, {(1450, 0), (350, 250)});
    expect(regions, hasLength(4));
    c.close();
    await server.close();
  });

  test('点击后先后到达的变化区域（高亮行、菜单）在更新停止后按外接矩形补刷新；滚轮不触发', () async {
    final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    final regions = <List<int>>[];
    late Socket sock;
    server.listen((s) async {
      sock = s;
      final r = AsyncByteReader(s);
      s.add('RFB 003.008\n'.codeUnits);
      await r.read(12);
      s.add([1, 1]);
      await r.u8();
      s.add([0, 0, 0, 0]);
      await r.u8();
      final init = ByteData(24)
        ..setUint16(0, 1920)
        ..setUint16(2, 1080)
        ..setUint32(20, 1);
      s.add([...init.buffer.asUint8List(), ...'t'.codeUnits]);
      // 首帧整屏（真实服务器连接后总会先发整屏）
      s.add([0, 0, 0, 1, ..._rect(0, 0, 1920, 1080, 0), ...Uint8List(1920 * 1080 * 4)]);
      try {
        while (true) {
          final t = await r.u8();
          if (t == 0) await r.read(19);
          if (t == 2) {
            final h = await r.read(3);
            await r.read(((h[1] << 8) | h[2]) * 4);
          }
          if (t == 3) {
            final q = ByteData.sublistView(await r.read(9));
            final region = [q.getUint16(1), q.getUint16(3), q.getUint16(5), q.getUint16(7)];
            if (q.getUint8(0) == 0 && region[2] != 1920) regions.add(region);
          }
          if (t == 4) await r.read(7);
          if (t == 5) {
            final p = await r.read(5);
            // 右键按下：先发高亮行（200,100 800×20），20ms 后发菜单（500,110 300×400）
            if (p[0] == 4) {
              s.add([0, 0, 0, 1, ..._rect(200, 100, 800, 20, 0), ...List.filled(800 * 20 * 4, 1)]);
              await Future.delayed(const Duration(milliseconds: 20));
              s.add([0, 0, 0, 1, ..._rect(500, 110, 300, 400, 0), ...List.filled(300 * 400 * 4, 2)]);
            }
          }
          if (t == 6) {
            await r.read(3);
            await r.read(await r.u32());
          }
        }
      } catch (_) {}
    });
    final c = RfbIsolateClient();
    c.onFrame = () => c.takeFrame();
    await c.connect('127.0.0.1', server.port);
    await Future.delayed(const Duration(milliseconds: 300));
    // 滚轮不触发补刷新
    c.sendPointer(100, 100, 16, input: true);
    c.sendPointer(100, 100, 0);
    await Future.delayed(const Duration(milliseconds: 600));
    expect(regions, isEmpty, reason: '滚轮不应触发补刷新');

    c.sendPointer(600, 105, 4, input: true);
    await Future.delayed(const Duration(milliseconds: 110));
    // 两块更新到达后约 30ms：按外接矩形（含 16 像素外扩）补刷新，早于固定的 120ms 补刷新
    expect(regions, isNotEmpty);
    expect(regions, anyElement(equals([184, 84, 832, 442])), reason: '覆盖高亮行与菜单的外接矩形');
    sock.destroy();
    c.close();
    await server.close();
  });
}
