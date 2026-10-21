import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:remlark/data/database.dart';
import 'package:remlark/modules/hosts/host_model.dart';
import 'package:remlark/modules/hosts/host_repository.dart';
import 'package:remlark/modules/remote_desktop/rdp/rdp_client.dart';
import 'package:remlark/modules/remote_desktop/rdp/rdp_h264.dart';
import 'package:remlark/utils/secret_store.dart';

/// 多平台测试 P-12：显式指定已授权的本地配置后，验证真实 RDP 主机；默认不访问用户数据或网络。
void main() {
  final dataPath = Platform.environment['RMK_RDP_LIVE_DATA_DIR'];
  final hostName = Platform.environment['RMK_RDP_LIVE_HOST'];
  final outputPath = Platform.environment['RMK_RDP_LIVE_OUTPUT'];
  test(
    '真实 RDP：硬解开关两种模式下认证、首帧、键盘触发更新与截图',
    () async {
      expect(RdpClient.isAvailable, isTrue, reason: '请先编译当前平台原生库');
      final key = File('$dataPath/master.key');
      final file = File('$dataPath/remlark.sqlite');
      expect(key.existsSync() && file.existsSync(), isTrue, reason: '需要现有应用数据目录');
      // 只在内存中解密保存的凭据，不记录密码；数据库禁止写入和迁移。
      SecretStore.initForTest(base64Decode(key.readAsStringSync().trim()));
      final db = AppDatabase(
        NativeDatabase(
          file,
          enableMigrations: false,
          setup: (connection) => connection.execute('PRAGMA query_only = ON'),
        ),
      );
      addTearDown(db.close);
      // 按 protocol 索引过滤，再从 RDP 配置中选取用户明确指定的主机。
      final hosts = await HostRepository(db).listByProtocols({HostProtocol.rdp});
      final matches = hosts.where((h) => h.name == hostName).toList();
      expect(matches.length, 1, reason: '指定的 RDP 主机名称必须唯一');
      final host = matches.single;
      expect(host.password?.isNotEmpty, isTrue, reason: '测试需要已保存的密码');
      final support = RdpH264Support.probe();
      // ignore: avoid_print
      print('LIVE capability: ${support.describe()}');
      final output = Directory(outputPath!);
      output.createSync(recursive: true);
      for (final hardware in [true, false]) {
        await _exercise(host, hardware, output);
      }
    },
    skip: dataPath == null || hostName == null || outputPath == null
        ? '需显式设置 RMK_RDP_LIVE_DATA_DIR / RMK_RDP_LIVE_HOST / RMK_RDP_LIVE_OUTPUT'
        : false,
    timeout: const Timeout(Duration(minutes: 2)),
  );
}

/// 连接真实主机，收集实际 BGRA 画面，并用可逆的开始菜单操作验证输入与持续更新。
Future<void> _exercise(HostEntry host, bool hardware, Directory output) async {
  final client = RdpClient();
  final connected = Completer<void>();
  String? failure;
  Uint8List? pixels;
  var frames = 0, width = 0, height = 0;
  final mode = hardware ? 'enabled' : 'disabled';
  client.onConnected = (_, _) => connected.complete();
  client.onAuthFailed = (_) => failure = 'authentication failed';
  client.onCertificate = (changed, _) {
    if (changed) failure = 'certificate changed';
  };
  client.onDisconnected = (code, _) {
    failure ??= 'disconnected: $code';
    if (!connected.isCompleted) connected.completeError(StateError(failure!));
  };
  client.onFrame = () {
    final update = client.takeFrame();
    if (update == null) return;
    if (pixels == null || width != update.width || height != update.height) {
      width = update.width;
      height = update.height;
      pixels = Uint8List(width * height * 4);
    }
    for (final p in update.patches) {
      for (var y = 0; y < p.h; y++) {
        final start = ((p.y + y) * width + p.x) * 4;
        pixels!.setRange(start, start + p.w * 4, p.bgra, y * p.w * 4);
      }
    }
    frames++;
  };
  try {
    final proxy = host.proxy;
    client.connect(
      RdpConnectOptions(
        host: host.address,
        port: host.port,
        username: host.username,
        password: host.password!,
        domain: host.extra['domain'] as String? ?? '',
        width: 1280,
        height: 800,
        hardwareDecode: hardware,
        knownFingerprint: host.hostKeyFingerprint,
        clipboard: false,
        tempDir: output.path,
        proxyType: proxy.enabled ? (proxy.type == ProxyType.http ? 1 : 2) : 0,
        proxyHost: proxy.host,
        proxyPort: proxy.port,
        proxyUser: proxy.username,
        proxyPassword: proxy.password ?? '',
      ),
    );
    await connected.future.timeout(const Duration(seconds: 25));
    await _wait(() => frames > 0, () => failure);
    // Windows 认证后仍可能停留在“请稍候”，等待桌面稳定再测试，避免登录动画造成假阳性。
    await Future<void>.delayed(const Duration(seconds: 8));
    // 清除上一会话可能保留的菜单状态，确保基线截图为正常桌面。
    client.sendKey(0x01, true);
    client.sendKey(0x01, false);
    await Future<void>.delayed(const Duration(milliseconds: 800));
    final before = Uint8List.fromList(pixels!);
    expect(before.any((v) => v != 0 && v != 255), isTrue, reason: '首帧应含图像数据');
    await _savePng(before, width, height, '${output.path}/$mode-first.png');
    final count = frames;
    // Windows 键打开开始菜单，Escape 关闭；不输入文字、不更改远程文件。
    client.sendKey(0x15B, true);
    client.sendKey(0x15B, false);
    try {
      await _wait(() => frames > count, () => failure);
      await Future<void>.delayed(const Duration(seconds: 2));
      final after = Uint8List.fromList(pixels!);
      final changed = Iterable<int>.generate(before.length).where((i) => before[i] != after[i]).length;
      expect(changed, greaterThan(100), reason: '开始菜单操作应改变远程画面');
      await _savePng(after, width, height, '${output.path}/$mode-menu.png');
      expect(failure, isNull, reason: '测试期间连接必须保持正常');
      // ignore: avoid_print
      print('LIVE $mode: ${width}x$height, frames=$frames, changedBytes=$changed');
    } finally {
      client.sendKey(0x01, true);
      client.sendKey(0x01, false);
      await Future<void>.delayed(const Duration(milliseconds: 500));
    }
  } finally {
    client.disconnect();
    client.dispose();
  }
}

/// 等待实际事件，及时报告断开，避免将静态首帧误认为输入更新成功。
Future<void> _wait(bool Function() ready, String? Function() failure) async {
  final deadline = DateTime.now().add(const Duration(seconds: 15));
  while (!ready()) {
    if (failure() != null) throw StateError(failure()!);
    if (DateTime.now().isAfter(deadline)) throw TimeoutException('RDP frame timeout');
    await Future<void>.delayed(const Duration(milliseconds: 50));
  }
}

/// 把实际解码后的 BGRA 帧保存为 PNG，供人工检查花屏与颜色。
Future<void> _savePng(Uint8List bgra, int width, int height, String path) async {
  final done = Completer<ui.Image>();
  ui.decodeImageFromPixels(bgra, width, height, ui.PixelFormat.bgra8888, done.complete);
  final image = await done.future;
  try {
    final png = await image.toByteData(format: ui.ImageByteFormat.png);
    await File(path).writeAsBytes(png!.buffer.asUint8List());
  } finally {
    image.dispose();
  }
}
