// UI 快照：设置环境变量 SNAPSHOT_DIR 时，把主要页面渲染为 PNG 以便目视检查
import 'dart:io';
import 'dart:ui' as ui;

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart' show PointerDeviceKind;
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:remlark/app/app.dart';
import 'package:remlark/app/app_services.dart';
import 'package:remlark/app/nav_controller.dart';
import 'package:remlark/data/database.dart';
import 'package:remlark/modules/ai/agent_config.dart';
import 'package:remlark/modules/ai/chat_controller.dart';
import 'package:remlark/modules/ai/terminal_agent/command_permission.dart';
import 'package:remlark/modules/ai/ui/command_permission_selector.dart';
import 'package:remlark/modules/ai/codex/codex_app_server.dart';
import 'package:remlark/modules/ai/codex/codex_environment.dart';
import 'package:remlark/modules/ai/codex/platform/codex_platform.dart';
import 'package:remlark/modules/ai/dsh/dsh_types.dart';
import 'package:remlark/modules/hosts/host_model.dart';
import 'package:remlark/modules/hosts/ui/host_editor_dialog.dart';
import 'package:remlark/modules/keys/key_model.dart';
import 'package:remlark/modules/remote_desktop/vnc/vnc_session.dart';
import 'package:remlark/modules/remote_desktop/rdp/rdp_session.dart';
import 'package:remlark/modules/settings/ui/agent_editor_dialog.dart';
import 'package:remlark/modules/ssh/ui/ssh_dialogs.dart';
import 'package:remlark/modules/terminal/terminal_session.dart';
import 'package:remlark/modules/terminal/ui/terminal_tab_view.dart';
import 'package:remlark/modules/workspace/workspace_tab.dart';
import 'package:remlark/utils/crypto_utils.dart';
import 'package:remlark/utils/id_utils.dart';
import 'package:remlark/utils/secret_store.dart';
import 'package:remlark/utils/ui_utils.dart';
import 'package:provider/provider.dart';

import 'helpers/fake_codex_server.dart';
import 'helpers/test_fonts.dart';

Future<void> _shot(WidgetTester tester, String name) async {
  // 不用 pumpAndSettle：连接中的转圈动画不会结束
  for (var i = 0; i < 4; i++) {
    await tester.runAsync(
      () => Future.delayed(const Duration(milliseconds: 80)),
    );
    await tester.pump(const Duration(milliseconds: 120));
  }
  final dir = Platform.environment['SNAPSHOT_DIR']!;
  final boundary = tester.renderObject<RenderRepaintBoundary>(
    find.byType(RepaintBoundary).first,
  );
  final image = await tester.runAsync(() => boundary.toImage(pixelRatio: 1));
  final bytes = await tester.runAsync(
    () => image!.toByteData(format: ui.ImageByteFormat.png),
  );
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
        (
          'db-master',
          'rhel',
          'Red Hat Enterprise Linux 9.2',
          HostProtocol.ssh,
          true,
        ),
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
            extra: proto == HostProtocol.vnc
                ? {
                    'ssh': {'enabled': true, 'port': 22},
                  }
                : const {},
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
      await services.keyRepo.save(
        KeyEntry(
          uuid: 'k1',
          name: 'production-ed25519',
          keyType: 'ssh-ed25519',
          privateKey: 'x',
          publicKey: 'ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIJ7h3K9pQ1mV4zF8nD6rT2wL0cJ5sG7kP9dQ1mN8xY2zA prod@server',
          createdAt: now,
        ),
      );
      await services.hosts.load();
      await services.hostRepo.save(
        services.hosts.all.first.copyWith(lastConnectedAt: () => now),
        touch: false,
      );
      await services.hosts.load();
    });
    await tester.pumpWidget(
      RepaintBoundary(child: RemlarkApp(services: services)),
    );
    NavController nav() =>
        UiUtils.navigatorKey.currentContext!.read<NavController>();
    await _shot(tester, '01_hosts');
    nav().go(AppPage.sessions);
    await _shot(tester, '06_workspace_empty');
    nav().go(AppPage.keys);
    await _shot(tester, '07_keys');
    nav().goSettings(SettingsSection.sync);
    await _shot(tester, '08_settings_sync');
    // AI Agent 设置：列表 + 编辑框中 DeepSeek Harness 运行环境的未安装 / 安装中 / 可更新三种状态
    await tester.runAsync(
      () => services.agents.save(
        const AgentSettings(uuid: 'a1', name: 'DeepSeek Harness', kind: AgentKind.deepseekCli, createdAt: 0),
      ),
    );
    nav().goSettings(SettingsSection.agents);
    await _shot(tester, '09_settings_agents');
    showDialog<void>(
      context: UiUtils.navigatorKey.currentContext!,
      builder: (_) => const AgentEditorDialog(),
    );
    await _shot(tester, '09_agent_dialog_missing');
    services.dsh
      ..stage = DshInstallStage.downloadingNode
      ..stageVersion = '24.22.0'
      ..progress = 0.42
      ..notifyListeners();
    await _shot(tester, '09_agent_dialog_installing');
    services.dsh
      ..stage = null
      ..progress = null
      ..installedVersion = '0.2.1-rc.1'
      ..latestVersion = '0.2.1-rc.2'
      ..notifyListeners();
    await _shot(tester, '09_agent_dialog_update');
    UiUtils.navigatorKey.currentState!.pop();
    services.dsh
      ..installedVersion = null
      ..latestVersion = null
      ..notifyListeners();
    // Codex：已安装时编辑框显示账号与模型（假 app-server 返回已登录账号与模型列表）
    CodexAppServer.shared = CodexAppServer(
      launcher: (_) async => FakeCodexServer().connection,
      workspace: () async => '/tmp/rmk-codex',
    );
    final codexRoot = Directory.systemTemp.createTempSync('rmk-codex-shot-');
    for (final f in ['runtime/bin/codex', 'runtime/bin/codex-code-mode-host']) {
      File('${codexRoot.path}/$f').createSync(recursive: true);
    }
    File('${codexRoot.path}/runtime/codex-package.json').writeAsStringSync('{"version":"0.163.0"}');
    CodexEnvironment.override = CodexEnvironment(codexRoot.path, CodexPlatform.current());
    services.codex.latestVersion = '0.163.0';
    showDialog<void>(
      context: UiUtils.navigatorKey.currentContext!,
      builder: (_) => const AgentEditorDialog(
        existing: AgentSettings(uuid: 'a2', name: 'Codex', kind: AgentKind.codex, model: 'gpt-b', createdAt: 0),
      ),
    );
    await _shot(tester, '09_agent_dialog_codex');
    UiUtils.navigatorKey.currentState!.pop();
    // OpenAI 兼容接口：模型输入框右侧“获取列表”，API Key 可切换显示
    showDialog<void>(
      context: UiUtils.navigatorKey.currentContext!,
      builder: (_) => const AgentEditorDialog(
        existing: AgentSettings(uuid: 'a4', name: 'Ollama', kind: AgentKind.openaiApi, createdAt: 0),
      ),
    );
    await _shot(tester, '09_agent_dialog_openai');
    UiUtils.navigatorKey.currentState!.pop();
    CodexEnvironment.override = null;
    codexRoot.deleteSync(recursive: true);
    services.codex
      ..installedVersion = null
      ..latestVersion = null;
    // 工作区：打开多个终端（不实际连接）
    final ui = DialogInteraction();
    final ssh = services.hosts.all
        .where((h) => h.protocol == HostProtocol.ssh)
        .toList();
    for (var i = 0; i < 4; i++) {
      final t = TerminalSession(ssh[i], services.connector, ui);
      t.setState(SessionState.connected);
      t.terminal.write(
        '\x1b[32mroot@${ssh[i].name}\x1b[0m:~# uptime\r\n 14:28:17 up 6 days,  2:41,  3 users,  load average: 0.12, 0.08, 0.05\r\n\x1b[32mroot@${ssh[i].name}\x1b[0m:~# ',
      );
      services.workspace.add(t);
    }
    final first = services.workspace.terminals.first;
    first.uiState['panel'] = SidePanel.ai;
    services.workspace.activate(first.id);
    nav().go(AppPage.sessions);
    await _shot(tester, '09_terminal_ai');
    // 发送快捷键：单独按 Enter 只换行不发送；Ctrl+Enter（macOS 为 ⌘Enter）发送
    final chatInput = find.byWidgetPredicate((w) => w is TextField && (w.decoration?.hintText ?? '').contains('Ctrl+Enter'));
    expect(chatInput, findsOneWidget);
    await tester.tap(chatInput);
    await tester.enterText(chatInput, '看下磁盘');
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();
    final firstChat = first.uiState['chat'] as ChatController;
    expect(firstChat.messages, isEmpty);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 300)));
    await tester.pump();
    expect(firstChat.messages.first.role, 'user');
    expect(firstChat.messages.first.content, startsWith('看下磁盘'));
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 300)));
    // 已有消息时切换 Agent：新建对话（换 Agent 无法续用原上下文与缓存），并设为默认 Agent
    await tester.runAsync(
      () => services.agents.save(
        const AgentSettings(uuid: 'a3', name: 'OpenAI', kind: AgentKind.openaiApi, createdAt: 2),
      ),
    );
    await tester.pump();
    await tester.tap(find.text('DeepSeek Harness').last);
    await tester.pump(const Duration(milliseconds: 200));
    await _shot(tester, '09_terminal_ai_agent_menu');
    await tester.tap(find.text('OpenAI').last);
    await tester.pump(const Duration(milliseconds: 200));
    expect(firstChat.messages, isEmpty);
    expect(services.agents.active?.uuid, 'a3');
    await tester.runAsync(() async {
      await services.agents.delete('a3');
      await services.agents.setActive('a1');
    });
    await tester.pump();
    // Codex：聊天窗口中可选择模型与推理强度
    final codexRoot2 = Directory.systemTemp.createTempSync('rmk-codex-shot-');
    for (final f in ['runtime/bin/codex', 'runtime/bin/codex-code-mode-host']) {
      File('${codexRoot2.path}/$f').createSync(recursive: true);
    }
    File('${codexRoot2.path}/runtime/codex-package.json').writeAsStringSync('{"version":"0.163.0"}');
    CodexEnvironment.override = CodexEnvironment(codexRoot2.path, CodexPlatform.current());
    await tester.runAsync(() async {
      await services.codex.loadLocal();
      await services.agents.save(
        const AgentSettings(
          uuid: 'a2',
          name: 'Codex',
          kind: AgentKind.codex,
          model: 'gpt-a',
          reasoningEffort: 'high',
          isActive: true,
          createdAt: 1,
        ),
      );
      await services.agentOptions.load(services.agents.active!);
    });
    await _shot(tester, '09_terminal_ai_codex');
    await tester.runAsync(() async {
      await services.agents.setActive('a1');
      services.codex.installedVersion = null;
    });
    CodexEnvironment.override = null;
    codexRoot2.deleteSync(recursive: true);
    // 逐条确认：命令已填入终端，等待按回车
    final chat = first.uiState['chat'] as ChatController;
    chat.messages.addAll([
      UiChatMessage('user', '帮我看下这台服务器硬盘多大'),
      UiChatMessage('assistant', '查看各分区的容量与使用情况\n\n```bash\ndf -h\n```'),
      UiChatMessage(
        'terminal',
        'root@bastion:~# df -h\nFilesystem      Size  Used Avail Use% Mounted on\n/dev/vda1        99G   41G   54G  44% /\nroot@bastion:~# ',
      ),
      UiChatMessage('assistant', '这台服务器系统盘 **/dev/vda1** 共 **99G**，已用 41G（44%），剩余 54G。'),
      UiChatMessage('user', '把 nginx 重启一下'),
      UiChatMessage('assistant', '重启 nginx 服务\n\n```bash\nsystemctl restart nginx\n```'),
    ]);
    chat.waitingForEnter = true;
    chat.notifyListeners();
    await _shot(tester, '09_terminal_ai_press_enter');
    chat.waitingForEnter = false;
    chat.messages.clear();
    // 聊天底部的命令权限菜单
    await tester.tap(find.byType(CommandPermissionSelector));
    await _shot(tester, '09_terminal_ai_permission_menu');
    await tester.tap(find.text('全部自动执行').last);
    await _shot(tester, '09_terminal_ai_permission_auto');
    chat.permission = CommandPermission.ask;
    services.workspace.openSftp(first);
    await _shot(tester, '10_sftp');
    services.workspace.showGrid();
    services.workspace.startBroadcast();
    await _shot(tester, '11_broadcast');
    services.workspace.stopBroadcast();
    await tester.runAsync(
      () => services.settings.setThemeMode(ThemeMode.light),
    );
    nav().go(AppPage.hosts);
    await _shot(tester, '12_hosts_light');
    // 真实鼠标悬停验证终端按钮反馈，截图后移开以免影响后续页面。
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: Offset.zero);
    await mouse.moveTo(tester.getCenter(find.byTooltip('连接 SSH 终端').first));
    await _shot(tester, '16_ssh_button_hover');
    await mouse.removePointer();
    nav().go(AppPage.sessions);
    services.workspace.activate(first.id);
    await _shot(tester, '13_terminal_light');
    // 第三版布局的混合协议、聚焦恢复及广播锁定快照。
    final w = services.workspace;
    final vnc = VncSession(
      services.hosts.all.firstWhere((h) => h.protocol == HostProtocol.vnc),
      services.hostRepo,
      services.connector,
      ui,
      ui,
    );
    final rdp = RdpSession(
      services.hosts.all.firstWhere((h) => h.protocol == HostProtocol.rdp),
      services.hostRepo,
      ui,
    );
    vnc.setState(SessionState.disconnected);
    rdp.setState(SessionState.disconnected);
    w.add(vnc);
    w.add(rdp);
    final gridIds = [first.id, w.terminals[1].id, vnc.id, rdp.id];
    w.showGrid(gridIds);
    await _shot(tester, '17_workspace_mixed_grid');
    final terminalElement = tester.element(find.byType(TerminalTabView).first);
    final header = find.byKey(ValueKey('grid-header-${first.id}'));
    await tester.tap(header);
    await tester.pump(const Duration(milliseconds: 80));
    await tester.tap(header);
    await tester.pump(const Duration(milliseconds: 300));
    expect(w.focusedGridId, first.id);
    expect(
      tester.element(find.byType(TerminalTabView).first),
      same(terminalElement),
    );
    await _shot(tester, '18_workspace_focused');
    await tester.tap(find.text('返回网格'));
    await tester.pump(const Duration(milliseconds: 200));
    expect(w.showingGrid, isTrue);
    expect(w.gridIds, gridIds);
    w.startBroadcast(ids: [first.id, w.terminals[1].id]);
    await _shot(tester, '19_workspace_broadcast');
    expect(w.showGrid([vnc.id]), isFalse);
    w.stopBroadcast();
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('workspace-layout')));
    await _shot(tester, '20_workspace_layout_menu');
    await tester.tap(find.text('单窗口').last);
    await tester.pump(const Duration(milliseconds: 200));
    for (final t in w.terminals.toList()) {
      await w.closeTab(t);
    }
    w.showGrid([vnc.id, rdp.id]);
    await _shot(tester, '21_workspace_desktops_only');
    expect(find.text('广播'), findsNothing);
    await tester.runAsync(() => services.settings.setThemeMode(ThemeMode.dark));
    nav().goSettings(SettingsSection.general);
    await _shot(tester, '02_settings');
    UiUtils.navigatorKey.currentContext!.read<NavController>().go(
      AppPage.snippets,
    );
    await _shot(tester, '03_snippets');
    UiUtils.navigatorKey.currentContext!.read<NavController>().go(AppPage.ai);
    await tester.runAsync(
      () => Future.delayed(const Duration(milliseconds: 300)),
    );
    await _shot(tester, '04_ai');
    UiUtils.navigatorKey.currentContext!.read<NavController>().go(
      AppPage.hosts,
    );
    await _shot(tester, '00_tmp');
    HostEditorDialog.show(
      UiUtils.navigatorKey.currentContext!,
      existing: services.hosts.all.first,
    );
    await tester.runAsync(
      () => Future.delayed(const Duration(milliseconds: 300)),
    );
    await _shot(tester, '05_editor');
    Navigator.of(UiUtils.navigatorKey.currentContext!).pop();
    HostEditorDialog.show(
      UiUtils.navigatorKey.currentContext!,
      existing: services.hosts.all.firstWhere(
        (h) => h.protocol == HostProtocol.vnc,
      ),
    );
    await _shot(tester, '14_dual_editor');
    expect(
      tester
          .widget<SegmentedButton<HostProtocol>>(
            find.byType(SegmentedButton<HostProtocol>),
          )
          .segments
          .length,
      3,
    );
    final sshSwitch = find.byKey(const ValueKey('vnc-enable-ssh'));
    await tester.ensureVisible(sshSwitch);
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(sshSwitch);
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('SSH 端口'), findsNothing);
    await tester.ensureVisible(sshSwitch);
    await tester.tap(sshSwitch);
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('SSH 端口'), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 500));
    await _shot(tester, '15_dual_ssh_settings');
    Navigator.of(UiUtils.navigatorKey.currentContext!).pop();
    await services.workspace.closeAll();
  });
}
