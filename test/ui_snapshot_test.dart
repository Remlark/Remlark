// UI 快照：设置环境变量 SNAPSHOT_DIR 时，把主要页面渲染为 PNG 以便目视检查
import 'dart:io';
import 'dart:ui' as ui;

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:remlark/app/app.dart';
import 'package:remlark/app/app_services.dart';
import 'package:remlark/app/nav_controller.dart';
import 'package:remlark/data/database.dart';
import 'package:remlark/modules/hosts/host_model.dart';
import 'package:remlark/modules/hosts/ui/host_editor_dialog.dart';
import 'package:remlark/utils/crypto_utils.dart';
import 'package:remlark/utils/id_utils.dart';
import 'package:remlark/utils/secret_store.dart';
import 'package:remlark/utils/ui_utils.dart';
import 'package:provider/provider.dart';

import 'helpers/test_fonts.dart';

Future<void> _shot(WidgetTester tester, String name) async {
  await tester.pumpAndSettle(const Duration(milliseconds: 300));
  final dir = Platform.environment['SNAPSHOT_DIR']!;
  final boundary = tester.renderObject<RenderRepaintBoundary>(find.byType(RepaintBoundary).first);
  final image = await tester.runAsync(() => boundary.toImage(pixelRatio: 1));
  final bytes = await tester.runAsync(() => image!.toByteData(format: ui.ImageByteFormat.png));
  File('$dir/$name.png').writeAsBytesSync(bytes!.buffer.asUint8List());
}

void main() {
  final dir = Platform.environment['SNAPSHOT_DIR'];
  testWidgets('页面快照', (tester) async {
    if (dir == null) return;
    await tester.runAsync(loadTestFonts);
    SecretStore.initForTest(CryptoUtils.randomBytes(32));
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1;
    final services = AppServices(AppDatabase(NativeDatabase.memory()));
    await tester.runAsync(() async {
      await services.init(installKeySnippetName: '系统免密登录');
      await services.settings.setLocale(const Locale('zh'));
      final g = await services.groupRepo.ensureByName('生产环境');
      await services.groupRepo.ensureByName('测试环境');
      final now = DateTime.now().millisecondsSinceEpoch;
      final samples = [
        ('web-01', 'ubuntu', 'Ubuntu 22.04.3 LTS', HostProtocol.ssh, true),
        ('db-master', 'rhel', 'Red Hat Enterprise Linux 9.2', HostProtocol.ssh, true),
        ('k8s-node', 'centos', 'CentOS Stream 9', HostProtocol.ssh, false),
        ('bastion', 'debian', 'Debian GNU/Linux 12', HostProtocol.ssh, false),
        ('win-server', null, null, HostProtocol.rdp, false),
        ('design-mac', 'macos', 'macOS 14.5', HostProtocol.vnc, false),
      ];
      for (final (name, os, osName, proto, sync) in samples) {
        await services.hostRepo.save(
          HostEntry(
            uuid: IdUtils.newId(),
            protocol: proto,
            name: name,
            groupUuid: g.uuid,
            address: '10.0.1.${name.length}',
            port: proto.defaultPort,
            username: 'root',
            osId: os,
            osName: osName,
            syncEnabled: sync,
            syncedAt: sync && name == 'web-01' ? now : null,
            jumpChain: name == 'db-master' ? ['x'] : const [],
            updatedAt: now,
            createdAt: now,
          ),
          touch: false,
        );
      }
      await services.hosts.load();
    });
    await tester.pumpWidget(RepaintBoundary(child: RemlarkApp(services: services)));
    await _shot(tester, '01_hosts');
    UiUtils.navigatorKey.currentContext!.read<NavController>().go(AppPage.settings);
    await _shot(tester, '02_settings');
    UiUtils.navigatorKey.currentContext!.read<NavController>().go(AppPage.snippets);
    await _shot(tester, '03_snippets');
    UiUtils.navigatorKey.currentContext!.read<NavController>().go(AppPage.ai);
    await tester.runAsync(() => Future.delayed(const Duration(milliseconds: 300)));
    await _shot(tester, '04_ai');
    UiUtils.navigatorKey.currentContext!.read<NavController>().go(AppPage.hosts);
    await tester.pumpAndSettle();
    HostEditorDialog.show(UiUtils.navigatorKey.currentContext!, existing: services.hosts.all.first);
    await tester.runAsync(() => Future.delayed(const Duration(milliseconds: 300)));
    await _shot(tester, '05_editor');
  });
}
