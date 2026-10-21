import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:remlark/app/app.dart';
import 'package:remlark/app/app_services.dart';
import 'package:remlark/app/nav_controller.dart';
import 'package:remlark/data/database.dart';
import 'package:remlark/l10n/app_localizations.dart';
import 'package:remlark/modules/remote_desktop/rdp/rdp_client.dart';
import 'package:remlark/modules/remote_desktop/rdp/rdp_h264.dart';
import 'package:remlark/modules/settings/settings_controller.dart';
import 'package:remlark/modules/settings/settings_repository.dart';
import 'package:remlark/utils/crypto_utils.dart';
import 'package:remlark/utils/secret_store.dart';
import 'package:remlark/utils/ui_utils.dart';

/// RDP 硬件解码设置：默认开启、持久化、设置页开关与本机能力一致
void main() {
  test('默认允许硬件解码，关闭后重新加载仍为关闭', () async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    final repo = SettingsRepository(db);
    final a = SettingsController(repo);
    await a.load();
    expect(a.rdpHardwareDecode, isTrue);
    await a.setRdpHardwareDecode(false);
    final b = SettingsController(repo);
    await b.load();
    expect(b.rdpHardwareDecode, isFalse);
  });

  test('日志描述区分硬件解码、软件解码与设置关闭', () {
    const hw = RdpH264Support(decoder: true, hardware: true, hwType: 'videotoolbox');
    expect(hw.describe(), contains('硬件解码'));
    expect(hw.describe(hardwareDecode: false), contains('设置中已关闭'));
    const sw = RdpH264Support(decoder: true, hardware: false, hwType: 'vaapi');
    expect(sw.describe(), contains('软件解码'));
    expect(RdpH264Support.unsupported.describe(), contains('未启用'));
    expect(const RdpH264Support(decoder: true, hardware: true, hwType: 'd3d11va').hwName, contains('D3D11VA'));
  });

  testWidgets('设置页：本机支持硬件解码时可切换，不支持时开关禁用', (tester) async {
    SecretStore.initForTest(CryptoUtils.randomBytes(32));
    final services = (await tester.runAsync(() async {
      final s = AppServices(AppDatabase(NativeDatabase.memory()));
      await s.init(installKeySnippetName: 'x');
      return s;
    }))!;
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(RemlarkApp(services: services));
    await tester.pump();
    UiUtils.navigatorKey.currentContext!.read<NavController>().goSettings(SettingsSection.remoteDesktop);
    await tester.pumpAndSettle();

    final t = S.current;
    expect(find.text(t.t('settings.rdp_hwdec')), findsOneWidget);
    final h264 = RdpClient.isAvailable ? RdpH264Support.probe() : null;
    final supported = h264 != null && h264.decoder && h264.hardware;
    final sw = find.byType(Switch);
    expect(tester.widget<Switch>(sw).value, supported);
    if (!supported) {
      expect(tester.widget<Switch>(sw).onChanged, isNull);
      return;
    }
    await tester.tap(sw);
    await tester.pumpAndSettle();
    expect(services.settings.rdpHardwareDecode, isFalse);
    expect(tester.widget<Switch>(sw).value, isFalse);
  });
}
