import 'dart:io';
import 'dart:typed_data';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:remlark/app/app.dart';
import 'package:remlark/app/app_services.dart';
import 'package:remlark/app/nav_controller.dart';
import 'package:remlark/data/database.dart';
import 'package:remlark/modules/hosts/host_model.dart';
import 'package:remlark/modules/hosts/ui/host_card.dart';
import 'package:remlark/modules/remote_desktop/vnc/vnc_session.dart';
import 'package:remlark/modules/remote_desktop/ui/vnc_view.dart';
import 'package:remlark/modules/ssh/ui/ssh_dialogs.dart';
import 'package:remlark/modules/workspace/ui/host_picker.dart';
import 'package:remlark/modules/workspace/workspace_tab.dart';
import 'package:remlark/modules/workspace/ui/workspace_host_card.dart';
import 'package:remlark/modules/workspace/ui/workspace_start_page.dart';
import 'package:remlark/utils/secret_store.dart';

import 'helpers/test_fonts.dart';

/// 保存真实组件截图；仅显式启用时写入构建目录，不影响日常回归。
Future<void> _capture(WidgetTester tester, String name) async {
  if (Platform.environment['WORKSPACE_SCREENSHOTS'] != '1') return;
  await tester.runAsync(
    () => Future<void>.delayed(const Duration(milliseconds: 200)),
  );
  await tester.pump();
  await expectLater(
    find.byKey(const ValueKey('workspace-preview')),
    matchesGoldenFile('../build/validation/workspace/$name.png'),
  );
}

/// 在内存数据库中构造大量主机，包含未连接主机及三协议主机。
Future<AppServices> _services() async {
  SecretStore.initForTest(Uint8List(32));
  final services = AppServices(AppDatabase(NativeDatabase.memory()));
  await services.init(installKeySnippetName: 'SSH');
  final group = await services.groupRepo.ensureByName('只用于搜索的分组');
  final now = DateTime.now().millisecondsSinceEpoch;
  for (var i = 0; i < 60; i++) {
    await services.hostRepo.save(
      HostEntry(
        uuid: 'server-$i',
        name: 'server-${i.toString().padLeft(2, '0')}',
        address: '10.0.0.$i',
        username: i == 59 ? 'search-account' : 'ubuntu',
        groupUuid: i == 59 ? group.uuid : null,
        protocol: HostProtocol.ssh,
        port: 22,
        osId: 'ubuntu',
        extra: i == 0
            ? {
                'connections': {
                  'rdp': {'port': 3389},
                  'vnc': {'port': 5900},
                },
              }
            : const {},
        createdAt: now,
        updatedAt: now,
        lastConnectedAt: i < 30 ? now - i * 3600000 : null,
      ),
      touch: false,
    );
  }
  await services.hosts.load();
  await services.settings.setLocale(const Locale('zh'));
  await services.settings.setThemeMode(ThemeMode.dark);
  return services;
}

/// 验证全页搜索、大量主机滚动、各主题语言布局和会话视图保留。
void main() {
  testWidgets('最近连接网格、全量搜索与新建会话页面保留远程视图', (tester) async {
    await tester.runAsync(loadTestFonts);
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1584, 992);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final services = (await tester.runAsync(_services))!;
    addTearDown(() async {
      services.updates.dispose();
      await services.workspace.closeAll();
      await services.db.close();
    });
    await tester.pumpWidget(
      RepaintBoundary(
        key: const ValueKey('workspace-preview'),
        child: RemlarkApp(services: services),
      ),
    );
    final nav = tester
        .element(find.byType(Scaffold).first)
        .read<NavController>();
    nav.go(AppPage.sessions);
    await tester.pumpAndSettle();
    expect(
      find.byType(WorkspaceHostCard).evaluate().length,
      greaterThanOrEqualTo(12),
    );
    expect(find.text('30'), findsOneWidget);
    final firstCard = find.byKey(const ValueKey('workspace-host-server-0'));
    final buttons = tester.widget<HostConnectButtons>(
      find.descendant(of: firstCard, matching: find.byType(HostConnectButtons)),
    );
    expect(buttons.host.extra['connections'], isNotNull);
    expect(
      find.descendant(of: firstCard, matching: find.byTooltip('连接 RDP 桌面')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: firstCard, matching: find.byTooltip('连接 VNC 桌面')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: firstCard, matching: find.byTooltip('连接 SSH 终端')),
      findsOneWidget,
    );
    await _capture(tester, 'recent-dark-zh');
    await tester.scrollUntilVisible(
      find.text('server-29'),
      350,
      scrollable: find
          .descendant(
            of: find.byType(WorkspaceStartPage),
            matching: find.byType(Scrollable),
          )
          .last,
    );
    expect(find.text('server-29'), findsOneWidget);

    // 搜索必须覆盖默认最近连接以外的主机，并且不会改写主机页的筛选。
    services.hosts.setSearch('unrelated-filter');
    final search = find.descendant(
      of: find.byType(WorkspaceStartPage),
      matching: find.byType(TextField),
    );
    for (final query in [
      'server-59',
      '10.0.0.59',
      'search-account',
      '只用于搜索的分组',
    ]) {
      await tester.enterText(search, query);
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('workspace-host-server-59')),
        findsOneWidget,
        reason: query,
      );
      expect(find.byType(WorkspaceHostCard), findsOneWidget);
    }
    expect(services.hosts.search, 'unrelated-filter');
    await tester.enterText(search, 'not-found');
    await tester.pumpAndSettle();
    expect(find.text('没有符合条件的主机'), findsOneWidget);
    await tester.enterText(search, '');
    await tester.tap(find.byKey(const ValueKey('workspace-browse-hosts')));
    await tester.pumpAndSettle();
    expect(find.text('60'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('workspace-browse-hosts')));
    await tester.pumpAndSettle();

    // 真实远程视图在进入新建会话页面时保留 Element 身份，不重复挂载。
    final ui = DialogInteraction();
    final desktop = VncSession(
      services.hosts.all.first.copyWith(protocol: HostProtocol.vnc, port: 5900),
      services.hostRepo,
      services.connector,
      ui,
      ui,
    )..state = SessionState.disconnected;
    services.workspace.add(desktop);
    await tester.pumpAndSettle();
    final view = tester.element(find.byType(VncView));
    await tester.tap(find.text('新建会话'));
    await tester.pumpAndSettle();
    expect(services.workspace.showingStartPage, isTrue);
    expect(find.byType(HostPicker), findsNothing);
    expect(
      tester.element(find.byType(VncView, skipOffstage: false)),
      same(view),
    );
    expect(find.byType(VncView), findsNothing);
    await tester.drag(find.byType(GridView).last, const Offset(0, 5000));
    await tester.pumpAndSettle();
    await _capture(tester, 'new-session-dark-zh');
    await tester.tap(find.byTooltip('返回当前会话'));
    await tester.pumpAndSettle();
    expect(services.workspace.showingStartPage, isFalse);
    expect(tester.element(find.byType(VncView)), same(view));
    services.workspace.showStartPage();
    await tester.pumpAndSettle();
    // 再次选择当前标签也必须退出开始页。
    await tester.tap(find.text(desktop.title).first);
    await tester.pumpAndSettle();
    expect(services.workspace.showingStartPage, isFalse);
    services.workspace.showStartPage();
    await tester.pumpAndSettle();

    for (final size in [const Size(1584, 992), const Size(960, 640)]) {
      tester.view.physicalSize = size;
      for (final language in ['en', 'zh']) {
        for (final mode in [ThemeMode.dark, ThemeMode.light]) {
          await tester.runAsync(() async {
            await services.settings.setLocale(Locale(language));
            await services.settings.setThemeMode(mode);
          });
          await tester.pumpAndSettle();
          expect(
            tester.takeException(),
            isNull,
            reason: '$size $language $mode',
          );
          await tester.drag(find.byType(GridView).last, const Offset(0, 5000));
          await tester.pumpAndSettle();
          await _capture(
            tester,
            '${size.width.toInt()}-$language-${mode.name}',
          );
        }
      }
    }
    await tester.pumpWidget(const SizedBox.shrink());
  });
  testWidgets('没有主机时提供管理入口，没有连接历史时直接浏览全部主机', (tester) async {
    await tester.runAsync(loadTestFonts);
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(960, 640);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    SecretStore.initForTest(Uint8List(32));
    final services = AppServices(AppDatabase(NativeDatabase.memory()));
    await tester.runAsync(() async {
      await services.init(installKeySnippetName: 'SSH');
      await services.settings.setLocale(const Locale('zh'));
    });
    addTearDown(() async {
      services.updates.dispose();
      await services.db.close();
    });
    await tester.pumpWidget(RemlarkApp(services: services));
    final nav = tester
        .element(find.byType(Scaffold).first)
        .read<NavController>();
    nav.go(AppPage.sessions);
    await tester.pumpAndSettle();
    expect(find.text('还没有主机，先添加一台主机开始连接。'), findsOneWidget);
    await tester.tap(find.text('管理主机'));
    await tester.pumpAndSettle();
    expect(nav.page, AppPage.hosts);
    await tester.runAsync(() async {
      await services.hostRepo.save(
        HostEntry(
          uuid: 'first',
          name: 'first-server',
          protocol: HostProtocol.ssh,
          address: 'localhost',
          port: 22,
          username: 'root',
          createdAt: 0,
          updatedAt: 0,
        ),
      );
      await services.hosts.load();
    });
    nav.go(AppPage.sessions);
    await tester.pumpAndSettle();
    expect(find.text('first-server'), findsOneWidget);
    expect(find.text('从未连接'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
