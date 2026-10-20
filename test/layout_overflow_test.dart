// 布局溢出检查：在最小窗口尺寸、默认尺寸与大尺寸下，以中英文渲染所有页面、对话框与会话视图，
// 任何 RenderFlex 溢出等渲染错误都会使测试失败
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:remlark/app/app.dart';
import 'package:remlark/app/app_services.dart';
import 'package:remlark/app/nav_controller.dart';
import 'package:remlark/app/window_config.dart';
import 'package:remlark/data/database.dart';
import 'package:remlark/l10n/app_localizations.dart';
import 'package:remlark/modules/ai/agent_config.dart';
import 'package:remlark/modules/hosts/host_model.dart';
import 'package:remlark/modules/hosts/ui/host_editor_dialog.dart';
import 'package:remlark/modules/keys/key_model.dart';
import 'package:remlark/modules/keys/ui/key_dialogs.dart';
import 'package:remlark/modules/remote_desktop/rdp/rdp_session.dart';
import 'package:remlark/modules/remote_desktop/vnc/vnc_session.dart';
import 'package:remlark/modules/snippets/snippet_model.dart';
import 'package:remlark/modules/snippets/ui/snippet_editor_dialog.dart';
import 'package:remlark/modules/ssh/ui/ssh_dialogs.dart';
import 'package:remlark/modules/terminal/terminal_session.dart';
import 'package:remlark/modules/terminal/ui/terminal_tab_view.dart';
import 'package:remlark/modules/workspace/ui/host_picker.dart';
import 'package:remlark/modules/workspace/ui/session_selection_dialog.dart';
import 'package:remlark/modules/workspace/workspace_controller.dart';
import 'package:remlark/modules/workspace/workspace_tab.dart';
import 'package:remlark/utils/crypto_utils.dart';
import 'package:remlark/utils/id_utils.dart';
import 'package:remlark/utils/secret_store.dart';
import 'package:remlark/utils/ui_utils.dart';

import 'helpers/test_fonts.dart';

const _long = 'production-database-master-node-with-a-very-long-name-01';

/// 写入测试数据：长名称的主机、分组、密钥、快捷指令、Agent、Token 与聊天记录
Future<AppServices> _seed() async {
  final s = AppServices(AppDatabase(NativeDatabase.memory()));
  await s.init(installKeySnippetName: '系统免密登录');
  final g = await s.groupRepo.ensureByName('生产环境-华东-可用区A-核心业务集群');
  for (var i = 0; i < 12; i++) {
    await s.groupRepo.ensureByName('分组 $i');
  }
  final now = DateTime.now().millisecondsSinceEpoch;
  for (var i = 0; i < 9; i++) {
    final proto = HostProtocol.values[i % 3];
    await s.hostRepo.save(
      HostEntry(
        uuid: IdUtils.newId(),
        protocol: proto,
        name: i == 0 ? _long : 'host-$i',
        groupUuid: g.uuid,
        address: 'very-long-hostname-$i.internal.example.corp.company.com',
        port: proto.defaultPort + i,
        username: 'administrator-account',
        extra: proto == HostProtocol.vnc
            ? {
                'ssh': {'enabled': true, 'port': 22},
              }
            : const {},
        osId: ['ubuntu', 'rhel', 'macos'][i % 3],
        osName:
            'Red Hat Enterprise Linux Server release 9.2 (Plow) long edition',
        jumpChain: i == 1 ? ['a', 'b'] : const [],
        proxy: i == 1
            ? const ProxyConfig(type: ProxyType.socks5, host: 'p', port: 1)
            : const ProxyConfig(),
        syncEnabled: i.isEven,
        lastConnectedAt: now - i,
        updatedAt: now,
        createdAt: now,
      ),
      touch: false,
    );
  }
  await s.keyRepo.save(
    KeyEntry(
      uuid: 'k',
      name: _long,
      keyType: 'ssh-ed25519',
      privateKey: 'x',
      publicKey: 'ssh-ed25519 ${'A' * 200} $_long',
      createdAt: now,
    ),
  );
  await s.snippetRepo.save(
    SnippetEntry(uuid: 's', name: _long, content: 'echo ${'x' * 300}'),
  );
  await s.agents.save(
    AgentSettings(
      uuid: 'a',
      name: 'DeepSeek Harness 智能助手（生产环境专用配置）',
      kind: AgentKind.deepseekCli,
      createdAt: now,
    ),
  );
  for (final model in [
    'deepseek-v4-pro-0813-with-long-name',
    'deepseek-chat',
  ]) {
    await s.tokenRepo.record(
      agentUuid: 'a',
      agentName: _long,
      model: model,
      input: 123456789,
      output: 98765432,
    );
  }
  final cs = await s.chatRepo.createSession(
    title: '如何排查 ${'很长的问题' * 20}',
    agentUuid: 'a',
    agentName: _long,
    model: 'm',
  );
  await s.chatRepo.addMessage(cs.id, 'user', '问题 ' * 100);
  await s.chatRepo.addMessage(
    cs.id,
    'assistant',
    '回答\n```bash\n${'ls -la /var/log/' * 20}\n```',
  );
  await s.hosts.load();
  return s;
}

/// 打开各种会话标签（不实际连接）
void _openTabs(AppServices s) {
  final ui = DialogInteraction();
  final hosts = s.hosts.all;
  for (var i = 0; i < 8; i++) {
    final h = hosts[i % hosts.length];
    final WorkspaceTab tab = switch (h.protocol) {
      HostProtocol.ssh => TerminalSession(h, s.connector, ui),
      HostProtocol.vnc => VncSession(h, s.hostRepo, s.connector, ui, ui),
      HostProtocol.rdp => RdpSession(h, s.hostRepo, ui),
    };
    if (tab is! TerminalSession) {
      tab.setState(SessionState.failed, error: '连接失败：${'很长的错误信息' * 10}');
    }
    s.workspace.add(tab);
  }
  // 再补足终端数量，覆盖广播 3×3 宫格
  final ssh = hosts.where((h) => h.protocol == HostProtocol.ssh).toList();
  for (var i = 0; i < 7; i++) {
    s.workspace.add(TerminalSession(ssh[i % ssh.length], s.connector, ui));
  }
  final terms = s.workspace.terminals;
  terms.first.uiState['panel'] = SidePanel.ai;
  // SFTP 独立标签（会话未连接，远程栏显示未连接状态）
  s.workspace.openSftp(terms[1]);
}

void main() {
  const sizes = [kMinWindowSize, kDefaultWindowSize, Size(1920, 1080)];

  for (final locale in const [Locale('zh'), Locale('en')]) {
    testWidgets('布局无溢出 ${locale.languageCode}', (tester) async {
      await tester.runAsync(loadTestFonts);
      SecretStore.initForTest(CryptoUtils.randomBytes(32));
      final services = (await tester.runAsync(_seed))!;
      await tester.runAsync(() => services.settings.setLocale(locale));
      final t = S(locale);
      final errors = <String>[];
      var where = '';
      final oldHandler = FlutterError.onError;
      FlutterError.onError = (d) {
        // 记录出错组件的源码位置，便于定位
        final loc =
            RegExp(r'(lib/[\w/]+\.dart:\d+)')
                .firstMatch(d.toString())
                ?.group(1) ??
            '';
        errors.add(
          '[$where] ${d.exceptionAsString().split('\n').first} @ $loc',
        );
      };

      /// 等待数据加载并渲染
      Future<void> settle() async {
        for (var i = 0; i < 3; i++) {
          await tester.runAsync(
            () => Future.delayed(const Duration(milliseconds: 60)),
          );
          await tester.pump(const Duration(milliseconds: 100));
        }
      }

      BuildContext ctx() => UiUtils.navigatorKey.currentContext!;
      NavController nav() => ctx().read<NavController>();

      /// 打开对话框、渲染并关闭
      Future<void> dialog(String name, void Function() open) async {
        where =
            '${locale.languageCode} ${tester.view.physicalSize} dialog:$name';
        open();
        await settle();
        Navigator.of(ctx()).pop();
        await settle();
      }

      try {
        await tester.pumpWidget(RemlarkApp(services: services));
        for (final size in sizes) {
          tester.view.physicalSize = size;
          tester.view.devicePixelRatio = 1;
          for (final page in AppPage.values) {
            where = '${locale.languageCode} $size page:${page.name}';
            nav().go(page);
            await settle();
            if (page == AppPage.ai) {
              await tester.tap(find.text(t.t('ai.tab.history')));
              await settle();
              await tester.tap(find.text(t.t('ai.tab.history')).first);
              await settle();
              await tester.tap(find.text(t.t('ai.tab.stats')));
              await settle();
            }
          }
          nav().go(AppPage.hosts);
          await settle();
          final host = services.hosts.all.first;
          for (final p in HostProtocol.values) {
            await dialog(
              'host-${p.name}',
              () => HostEditorDialog.show(ctx(), protocol: p),
            );
          }
          await dialog(
            'host-dual',
            () => HostEditorDialog.show(
              ctx(),
              existing: services.hosts.all.firstWhere(
                (h) => h.protocol == HostProtocol.vnc,
              ),
            ),
          );
          services.hosts.setListView(true);
          await settle();
          services.hosts.setListView(false);
          await settle();
          await dialog(
            'host-edit',
            () => HostEditorDialog.show(ctx(), existing: host),
          );
          await dialog(
            'snippet',
            () => showDialog(
              context: ctx(),
              builder: (_) => const SnippetEditorDialog(nextOrder: 0),
            ),
          );
          await dialog('key-import', () => KeyDialogs.import(ctx()));
          await dialog(
            'password',
            () =>
                DialogInteraction().askPassword(host, error: 'wrong_password'),
          );
          await dialog(
            'hostkey',
            () => DialogInteraction().confirmHostKeyChanged(
              host,
              'ssh-ed25519',
              'SHA256:${'a' * 43}',
              'SHA256:${'b' * 43}',
            ),
          );
          for (final sec in SettingsSection.values) {
            where = '${locale.languageCode} $size settings:${sec.name}';
            nav().goSettings(sec);
            await settle();
          }
          nav().goSettings(SettingsSection.agents);
          await settle();
          await dialog('agent', () => tester.tap(find.text(t.t('agent.new'))));
          nav().goSettings(SettingsSection.data);
          await settle();
          await dialog(
            'export',
            () => tester.tap(find.text(t.t('data.export')).last),
          );
          await dialog(
            'host-picker',
            () => HostPicker.show(ctx(), title: t.t('workspace.new_session')),
          );
        }

        // 会话工作区：多个标签、终端侧边面板、远程桌面状态，以及平铺与广播
        _openTabs(services);
        for (final size in sizes) {
          tester.view.physicalSize = size;
          nav().go(AppPage.sessions);
          for (final tab in services.workspace.tabs) {
            where = '${locale.languageCode} $size tab:${tab.runtimeType}';
            services.workspace.activate(tab.id);
            await settle();
          }
          // 混合协议网格覆盖 1–9 个会话，广播不改变布局。
          final w = services.workspace;
          final ids = w.gridCandidates.map((e) => e.id).toList();
          for (var n = 1; n <= WorkspaceController.maxGrid; n++) {
            where = '${locale.languageCode} $size grid:$n';
            w.showGrid(ids.take(n));
            await settle();
          }
          await dialog(
            'grid-selection',
            () => SessionSelectionDialog.show(ctx(), w),
          );
          await dialog(
            'broadcast-selection',
            () => SessionSelectionDialog.show(ctx(), w, broadcast: true),
          );
          w.focusGridSession(ids.first);
          await settle();
          w.returnToGrid();
          w.startBroadcast(ids: w.terminals.take(2).map((t) => t.id));
          where = '${locale.languageCode} $size broadcast';
          await settle();
          expect(w.showGrid(ids.take(2)), isFalse);
          expect(w.gridIds.length, 9);
          w.stopBroadcast();
          w.showSingle();
          await settle();
        }

        // 浅色主题：最小尺寸下渲染所有页面
        await tester.runAsync(
          () => services.settings.setThemeMode(ThemeMode.light),
        );
        tester.view.physicalSize = kMinWindowSize;
        for (final page in AppPage.values) {
          where = '${locale.languageCode} light page:${page.name}';
          nav().go(page);
          await settle();
        }
        await tester.runAsync(
          () => services.settings.setThemeMode(ThemeMode.dark),
        );
      } finally {
        FlutterError.onError = oldHandler;
        for (final e in errors.toSet()) {
          debugPrint('ERR $e');
        }
      }
      await services.workspace.closeAll();
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
      expect(
        errors.toSet().toList(),
        isEmpty,
        reason: errors.toSet().join('\n'),
      );
    });
  }
}
