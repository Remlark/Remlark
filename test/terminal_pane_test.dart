// 终端面板：已连接状态下应撑满内容区；从其他页面切回工作区后键盘焦点回到终端
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:remlark/app/app.dart';
import 'package:remlark/app/app_services.dart';
import 'package:remlark/app/nav_controller.dart';
import 'package:remlark/data/database.dart';
import 'package:remlark/l10n/app_localizations.dart';
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
    // 菜单读取剪贴板文件时使用确定的空结果，避免依赖宿主原生插件。
    const pasteboard = MethodChannel('pasteboard');
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      pasteboard, (call) async => <String>[],
    );
    addTearDown(() => tester.binding.defaultBinaryMessenger
        .setMockMethodCallHandler(pasteboard, null));
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async => call.method == 'Clipboard.hasStrings'
          ? <String, Object>{'value': false}
          : null,
    );
    addTearDown(() => tester.binding.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null));
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

    // 工具栏恢复全部样式，但不清屏、不移动光标，也不发送输入到远端。
    final terminal = session.terminal;
    final sent = <String>[];
    terminal.onOutput = sent.add;
    terminal.write('\x1b[1;2;3;4;5;7;8;9;35;44mOLD');
    final oldCell = CellData.empty();
    terminal.buffer.lines[0].getCellData(0, oldCell);
    final cursor = (terminal.buffer.cursorX, terminal.buffer.cursorY);
    await tester.tap(find.byKey(const ValueKey('terminal-reset-text-style')));
    await tester.pump();
    expect(terminal.cursor.foreground, 0);
    expect(terminal.cursor.background, 0);
    expect(terminal.cursor.attrs, 0);
    expect((terminal.buffer.cursorX, terminal.buffer.cursorY), cursor);
    final preserved = CellData.empty();
    terminal.buffer.lines[0].getCellData(0, preserved);
    expect(preserved.toString(), oldCell.toString());
    terminal.write('NEW');
    final normal = CellData.empty();
    terminal.buffer.lines[0].getCellData(3, normal);
    expect((normal.foreground, normal.background, normal.flags), (0, 0, 0));
    expect(sent, isEmpty);

    // 右键入口使用相同恢复动作，关闭菜单后仍可在终端继续输入。
    terminal.write('\x1b[1;35m');
    final mouse = await tester.startGesture(
      tester.getCenter(find.byType(TerminalView)),
      kind: PointerDeviceKind.mouse,
      buttons: kSecondaryMouseButton,
    );
    await tester.pump(const Duration(milliseconds: 150));
    await mouse.up();
    await tester.pumpAndSettle();
    await tester.tap(find.text(S.current.t('terminal.reset_text_style')).last);
    await tester.pumpAndSettle();
    expect(terminal.cursor.foreground, 0);
    expect(terminal.cursor.attrs, 0);
    expect(sent, isEmpty);

    // 手动恢复不会把本地控制字节插入尚未收完整的远端 CSI。
    terminal.write('\x1b[35m\x1b[');
    session.resetTextStyle();
    terminal.write('0mOK');
    expect(terminal.buffer.lines[0].getText().trimRight(), 'OLDNEWOK');
    expect(terminal.cursor.foreground, 0);
    expect(sent, isEmpty);

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
