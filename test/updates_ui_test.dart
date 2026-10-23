import 'dart:io';
import 'dart:typed_data';

import 'package:remlark/utils/secret_store.dart';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:remlark/app/app.dart';
import 'package:remlark/app/app_services.dart';
import 'package:remlark/app/nav_controller.dart';
import 'package:remlark/app/theme/app_palette.dart';
import 'package:remlark/app/theme/app_theme.dart';
import 'package:remlark/data/database.dart';
import 'package:remlark/l10n/app_localizations.dart';
import 'package:remlark/modules/settings/settings_repository.dart';
import 'package:remlark/modules/updates/ui/updates_section.dart';
import 'package:remlark/modules/updates/update_release.dart';
import 'package:remlark/modules/updates/updates_controller.dart';

import 'helpers/test_fonts.dart';

/// 构造包含当前平台附件的示例新版，不访问 GitHub。
UpdateRelease _release(UpdatesController controller) => UpdateRelease(
  '1.2.0',
  '### Improvements\n\n- 更稳定的远程连接 / More reliable connections\n- 修复文件传输问题 / File transfer fixes',
  [UpdateAsset(1, controller.platform.assetName('1.2.0')!, 91234567, null)],
);

/// 更新页中英文、深浅主题、各状态及可选完整应用截图。
void main() {
  testWidgets('更新页所有状态在最小内容宽度无溢出，无 Token 输入或保存路径操作', (tester) async {
    await tester.runAsync(loadTestFonts);
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(468, 640);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    final c = UpdatesController(
      SettingsRepository(db),
      currentVersion: '1.0.0+1',
    );
    addTearDown(c.dispose);
    for (final locale in ['zh', 'en']) {
      for (final brightness in Brightness.values) {
        for (final state in [
          'unchecked',
          'available',
          'checking',
          'downloading',
          'installing',
          'error',
        ]) {
          c.release = state == 'unchecked' ? null : _release(c);
          c.checking = state == 'checking';
          c.downloading = state == 'downloading';
          c.installing = state == 'installing';
          c.error = state == 'error' ? 'updates.error.not_found' : null;
          c.received = 100;
          c.total = 200;
          await tester.pumpWidget(
            ChangeNotifierProvider.value(
              value: c,
              child: MaterialApp(
                key: ValueKey('$locale-$brightness-$state'),
                locale: Locale(locale),
                supportedLocales: S.supportedLocales,
                localizationsDelegates: const [
                  S.delegate,
                  GlobalMaterialLocalizations.delegate,
                  GlobalWidgetsLocalizations.delegate,
                  GlobalCupertinoLocalizations.delegate,
                ],
                theme: AppTheme.build(brightness, AccentPreset.sage),
                home: const Scaffold(
                  body: SingleChildScrollView(
                    padding: EdgeInsets.all(16),
                    child: UpdatesSection(),
                  ),
                ),
              ),
            ),
          );
          await tester.pump(const Duration(milliseconds: 300));
          expect(
            tester.takeException(),
            isNull,
            reason: '$locale $brightness $state',
          );
          expect(find.byType(TextField), findsNothing);
        }
      }
    }
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('完整设置页截图与新版侧栏提示', (tester) async {
    await tester.runAsync(loadTestFonts);
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1440, 900);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    SecretStore.initForTest(Uint8List(32));
    final services = AppServices(AppDatabase(NativeDatabase.memory()));
    addTearDown(() {
      services.updates.dispose();
      return services.db.close();
    });
    await tester.runAsync(() => services.init(installKeySnippetName: 'SSH'));
    await tester.runAsync(() async {
      await services.settings.setLocale(const Locale('zh'));
      await services.settings.setThemeMode(ThemeMode.light);
    });
    services.updates.release = _release(services.updates);
    await tester.pumpWidget(
      RepaintBoundary(
        key: const ValueKey('updates-preview'),
        child: RemlarkApp(services: services),
      ),
    );
    await tester.pumpAndSettle();
    final nav = tester
        .element(find.byType(Scaffold).first)
        .read<NavController>();
    nav.goSettings(SettingsSection.updates);
    await tester.pumpAndSettle();
    expect(
      find.text('升级并重启'),
      services.updates.currentVersion == 'development'
          ? findsNothing
          : findsOneWidget,
    );
    expect(tester.takeException(), isNull);
    if (services.updates.currentVersion != 'development') {
      expect(find.text('新版本 1.2.0'), findsOneWidget);
    }
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 100)),
    );
    await tester.pump();
    if (Platform.environment['UPDATE_SCREENSHOTS'] == '1') {
      await expectLater(
        find.byKey(const ValueKey('updates-preview')),
        matchesGoldenFile('../build/validation/updates/settings-zh.png'),
      );
    }
    await tester.runAsync(() async {
      await services.settings.setLocale(const Locale('en'));
      await services.settings.setThemeMode(ThemeMode.dark);
    });
    await tester.pumpAndSettle();
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 100)),
    );
    await tester.pump();
    if (Platform.environment['UPDATE_SCREENSHOTS'] == '1') {
      await expectLater(
        find.byKey(const ValueKey('updates-preview')),
        matchesGoldenFile('../build/validation/updates/settings-en-dark.png'),
      );
    }
    tester.view.physicalSize = const Size(960, 640);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
