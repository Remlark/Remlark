import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:drift/native.dart';
import 'package:flutter/services.dart';
import 'package:remlark/data/database.dart';
import 'package:remlark/modules/hosts/host_model.dart';
import 'package:remlark/modules/hosts/host_repository.dart';
import 'package:remlark/modules/remote_desktop/rdp/rdp_client.dart';
import 'package:remlark/modules/remote_desktop/rdp/rdp_scancode.dart';
import 'package:remlark/modules/remote_desktop/rdp/rdp_session.dart';
import 'package:remlark/modules/remote_desktop/remote_desktop_interaction.dart';
import 'package:remlark/modules/ssh/ssh_interaction.dart';
import 'package:remlark/modules/workspace/workspace_tab.dart';
import 'package:remlark/utils/crypto_utils.dart';
import 'package:remlark/utils/platform_utils.dart';
import 'package:remlark/utils/secret_store.dart';

/// 测试交互：记录是否被询问密码
class _Ui implements RemoteDesktopInteraction {
  int asked = 0;

  @override
  Future<PasswordInput?> askDesktopPassword(HostEntry host, {String? error}) async {
    asked++;
    return const PasswordInput('pw');
  }

  @override
  Future<bool> confirmCertificateChanged(HostEntry host, String oldFingerprint, String newFingerprint) async => false;
}

/// 使用 FreeRDP 示例服务端（native/rdp/scripts/build_test_server.sh 编译）做端到端测试
void main() {
  final arch = Platform.isMacOS ? (Process.runSync('uname', ['-m']).stdout as String).trim() : 'x86_64';
  final os = Platform.isMacOS ? 'macos' : 'linux';
  final server = File('build/native/$os-$arch/test-server-build/server/Sample/sfreerdp-server');
  final available = server.existsSync() && RdpClient.isAvailable;
  late Directory dir;
  late Process proc;
  late int port;

  setUpAll(() async {
    if (!available) return;
    dir = Directory.systemTemp.createTempSync('rmk_rdp');
    await Process.run('openssl', [
      'req',
      '-x509',
      '-newkey',
      'rsa:2048',
      '-nodes',
      '-days',
      '1',
      '-subj',
      '/CN=localhost',
      '-keyout',
      '${dir.path}/server.key',
      '-out',
      '${dir.path}/server.crt',
    ]);
    for (final f in ['test_icon.png', 'test_icon.bmp']) {
      File('native/rdp/.deps/FreeRDP-3.32.2/server/Sample/$f').copySync('${dir.path}/$f');
    }
    port = int.tryParse(Platform.environment['RDP_TEST_PORT'] ?? '') ?? 33000 + DateTime.now().millisecond;
    proc = await Process.start(server.absolute.path, [
      '--cert=server.crt',
      '--key=server.key',
      '--port=$port',
    ], workingDirectory: dir.path);
    proc.stdout.listen((_) {});
    proc.stderr.listen((_) {});
    for (var i = 0; i < 50; i++) {
      try {
        (await Socket.connect('127.0.0.1', port)).destroy();
        break;
      } catch (_) {
        await Future.delayed(const Duration(milliseconds: 100));
      }
    }
  });

  tearDownAll(() {
    if (!available) return;
    proc.kill();
    dir.deleteSync(recursive: true);
  });

  /// 连接并等待第一帧，返回客户端与记录到的证书指纹
  Future<(RdpClient, String?)> connect({String? known}) async {
    final c = RdpClient();
    final connected = Completer<void>();
    final frame = Completer<void>();
    String? fp;
    c.onCertificate = (changed, f) => fp = changed ? 'CHANGED:$f' : f;
    c.onConnected = (w, h) => connected.complete();
    c.onFrame = () {
      if (!frame.isCompleted) frame.complete();
    };
    c.onDisconnected = (code, msg) {
      if (!connected.isCompleted) connected.completeError('disconnected $code $msg');
    };
    c.connect(
      RdpConnectOptions(
        host: '127.0.0.1',
        port: port,
        username: 'test',
        password: 'test',
        width: 1024,
        height: 768,
        knownFingerprint: known,
        tempDir: dir.path,
        sharedDir: dir.path,
      ),
    );
    await connected.future.timeout(const Duration(seconds: 20));
    await frame.future.timeout(const Duration(seconds: 20));
    return (c, fp);
  }

  test('连接、首次记录证书指纹、接收画面、鼠标输入触发画面更新', () async {
    if (!available) return markTestSkipped('RDP test server or native library not built');
    expect(RdpClient.version, startsWith('3.'));
    final (c, fp) = await connect();
    expect(fp, matches(RegExp('^[0-9a-f]{2}:')));
    final first = c.copyFrame()!;
    expect(c.width, greaterThan(0));
    expect(first.length, c.width * c.height * 4);
    expect(first.any((b) => b != 0 && b != 255), isTrue, reason: 'frame should contain image data');

    // 示例服务端会在鼠标位置绘制图标，画面应发生变化
    final next = Completer<void>();
    c.onFrame = () {
      if (!next.isCompleted) next.complete();
    };
    c.sendMouse(RdpPointer.move, 200, 200);
    await next.future.timeout(const Duration(seconds: 10));
    final second = c.copyFrame()!;
    var diff = 0;
    for (var i = 0; i < second.length; i++) {
      if (second[i] != first[i]) diff++;
    }
    expect(diff, greaterThan(0));
    c.disconnect();
    c.dispose();

    // 再次连接：已知指纹一致则正常；指纹不一致则被拒绝
    final (c2, fp2) = await connect(known: fp);
    expect(fp2, isNull);
    c2.disconnect();
    c2.dispose();

    final c3 = RdpClient();
    final rejected = Completer<String>();
    String? changed;
    c3.onCertificate = (ch, f) => changed = ch ? f : null;
    c3.onDisconnected = (code, msg) => rejected.complete('$code');
    c3.connect(
      RdpConnectOptions(
        host: '127.0.0.1',
        port: port,
        username: 't',
        password: 't',
        width: 800,
        height: 600,
        knownFingerprint: 'aa:bb',
      ),
    );
    await rejected.future.timeout(const Duration(seconds: 20));
    expect(changed, fp);
    c3.dispose();
  });

  test('RdpSession：未保存密码时询问、记录证书指纹、画面与输入、关闭', () async {
    if (!available) return markTestSkipped('RDP test server or native library not built');
    TestWidgetsFlutterBinding.ensureInitialized();
    SecretStore.initForTest(CryptoUtils.randomBytes(32));
    PlatformUtils.overrideDataDir(dir);
    final repo = HostRepository(AppDatabase(NativeDatabase.memory()));
    final host = await repo.save(
      HostEntry(
        uuid: 'r1',
        protocol: HostProtocol.rdp,
        name: 'win',
        address: '127.0.0.1',
        port: port,
        username: 'admin',
        updatedAt: 0,
        createdAt: 0,
      ),
    );
    final ui = _Ui();
    final s = RdpSession(host, repo, ui);
    s.viewResized(1100, 700);
    var frames = 0;
    s.addListener(() => frames++);
    await s.connect().timeout(const Duration(seconds: 30));
    expect(s.state, SessionState.connected);
    expect(ui.asked, 1);
    expect((await repo.getByUuid('r1'))!.hostKeyFingerprint, isNotEmpty);
    for (var i = 0; i < 50 && s.readFrame() == null; i++) {
      await Future.delayed(const Duration(milliseconds: 100));
    }
    final frame = s.readFrame();
    expect(frame, isNotNull);
    expect(frame!.length, s.frameWidth * s.frameHeight * 4);
    // 输入：鼠标按下 / 抬起、滚轮、键盘（扫描码映射）
    s.pointerEvent(100, 100, 1);
    s.pointerEvent(110, 110, 0);
    s.scrollEvent(110, 110, -1);
    expect(RdpScancode.fromKey(PhysicalKeyboardKey.keyA), 0x1E);
    expect(RdpScancode.fromKey(PhysicalKeyboardKey.arrowUp), 0x148);
    expect(RdpScancode.fromKey(PhysicalKeyboardKey.metaLeft, metaAsCtrl: true), 0x1D);
    await Future.delayed(const Duration(milliseconds: 500));
    expect(frames, greaterThan(0));
    await s.close();
  });
}
