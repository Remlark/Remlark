import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:remlark/app/app_services.dart';
import 'package:remlark/data/database.dart';
import 'package:remlark/modules/hosts/host_model.dart';
import 'package:remlark/modules/remote_desktop/vnc/vnc_session.dart';
import 'package:remlark/modules/ssh/ui/ssh_dialogs.dart';
import 'package:remlark/modules/workspace/workspace_tab.dart';
import 'package:remlark/utils/async_byte_reader.dart';
import 'package:remlark/utils/crypto_utils.dart';
import 'package:remlark/utils/secret_store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('连接后释放全部修饰键；按住 ⌘ 时失去焦点会发送 ⌘ 抬起（避免远程 ⌘ 卡住）', () async {
    SecretStore.initForTest(CryptoUtils.randomBytes(32));
    final services = AppServices(AppDatabase(NativeDatabase.memory()));
    await services.init(installKeySnippetName: 'x');
    final keys = <(int, bool)>[];
    final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
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
          if (t == 3) await r.read(9);
          if (t == 4) {
            final b = await r.read(7);
            keys.add((ByteData.sublistView(b).getUint32(3), b[0] == 1));
          }
          if (t == 5) await r.read(5);
          if (t == 6) {
            await r.read(3);
            await r.read(await r.u32());
          }
        }
      } catch (_) {}
    });
    final host = HostEntry(
      uuid: 'v',
      protocol: HostProtocol.vnc,
      name: 'vnc',
      address: '127.0.0.1',
      port: server.port,
      updatedAt: 0,
      createdAt: 0,
    );
    final ui = DialogInteraction();
    final s = VncSession(host, services.hostRepo, services.connector, ui, ui);
    await s.connect();
    expect(s.state, SessionState.connected);
    Future<void> settle() => Future.delayed(const Duration(milliseconds: 200));
    await settle();
    // 连接后：10 个修饰键全部发送抬起
    expect(keys.where((k) => !k.$2).map((k) => k.$1).toSet(), containsAll([0xffe1, 0xffe3, 0xffe9, 0xffeb, 0xffec]));
    keys.clear();

    // 按下左 ⌘ 后失去焦点（如 ⌘+Tab 切走，抬起事件被其他应用收到）
    s.keyEvent(
      const KeyDownEvent(
        physicalKey: PhysicalKeyboardKey.metaLeft,
        logicalKey: LogicalKeyboardKey.metaLeft,
        timeStamp: Duration.zero,
      ),
    );
    s.displayBlurred();
    await settle();
    expect(keys, [(0xffeb, true), (0xffeb, false)]);
    await s.close();
    await server.close();
  });
}
