// 终端面板：已连接状态下应撑满内容区；从其他页面切回工作区后键盘焦点回到终端
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:remlark/app/app.dart';
import 'package:remlark/app/app_services.dart';
import 'package:remlark/app/nav_controller.dart';
import 'package:remlark/data/database.dart';
import 'package:remlark/modules/hosts/host_model.dart';
import 'package:remlark/modules/ssh/ui/ssh_dialogs.dart';
import 'package:remlark/modules/terminal/terminal_session.dart';
import 'package:remlark/modules/workspace/workspace_tab.dart';
import 'package:remlark/utils/crypto_utils.dart';
import 'package:remlark/utils/secret_store.dart';
import 'package:remlark/utils/ui_utils.dart';
import 'package:xterm/xterm.dart';

import 'helpers/test_fonts.dart';

void main() {
  testWidgets('已连接的终端撑满区域且切页返回后可继续输入', (tester) async {
    await tester.runAsync(loadTestFonts);
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
    final host = HostEntry(
      uuid: 'h',
      protocol: HostProtocol.ssh,
      name: 'mac',
      address: '127.0.0.1',
      port: 22,
      username: 'u',
      updatedAt: 0,
      createdAt: 0,
    );
    final session = TerminalSession(host, services.connector, DialogInteraction());
    session.setState(SessionState.connected);
    services.workspace.add(session);
    final nav = UiUtils.navigatorKey.currentContext!.read<NavController>();
    nav.go(AppPage.sessions);
    await tester.pump();
    await tester.pump();

    // 连接后终端高度不能塌缩：应占据工具栏与状态栏之间的大部分区域
    final size = tester.getSize(find.byType(TerminalView));
    expect(size.height, greaterThan(500));
    expect(session.terminal.viewHeight, greaterThan(20));

    // 切到其他页面再回来，焦点应回到终端
    Widget? focusOf() => FocusManager.instance.primaryFocus?.context?.findAncestorWidgetOfExactType<TerminalView>();
    nav.go(AppPage.hosts);
    await tester.pump();
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pump();
    nav.go(AppPage.sessions);
    await tester.pump();
    await tester.pump();
    expect(focusOf(), isNotNull);
  });
}
