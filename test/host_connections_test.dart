import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:remlark/modules/hosts/ui/hosts_page.dart';
import 'package:remlark/ui_kit/buttons.dart';
import 'package:remlark/ui_kit/panel.dart';
import 'package:remlark/app/theme/app_palette.dart';
import 'package:remlark/app/theme/app_theme.dart';
import 'package:remlark/data/database.dart';
import 'package:remlark/modules/hosts/group_repository.dart';
import 'package:remlark/modules/hosts/host_model.dart';
import 'package:remlark/modules/hosts/host_repository.dart';
import 'package:remlark/modules/hosts/hosts_controller.dart';
import 'package:remlark/modules/hosts/ui/host_card.dart';

/// 双协议主机仅占用一条记录，两种连接使用各自端口。
final dualHost = HostEntry(
  uuid: 'dual',
  protocol: HostProtocol.vnc,
  name: 'Mac',
  address: 'mac.local',
  port: 5901,
  username: 'user',
  updatedAt: 0,
  createdAt: 0,
  extra: {
    'ssh': {'enabled': true, 'port': 2222},
  },
);

/// 验证双协议主机在筛选和连接入口中的一致行为。
void main() {
  test('同一主机出现在 SSH 和 VNC 筛选中，跳板候选使用 SSH 端口', () async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    final controller = HostsController(HostRepository(db), GroupRepository(db));
    addTearDown(controller.dispose);
    controller.all.add(dualHost);
    for (final filter in [
      ProtocolFilter.ssh,
      ProtocolFilter.vnc,
      ProtocolFilter.all,
    ]) {
      controller.setProtocolFilter(filter);
      expect(controller.visible.single.uuid, 'dual');
    }
    controller.setProtocolFilter(ProtocolFilter.rdp);
    expect(controller.visible, isEmpty);
    expect(controller.sshHosts.single.protocol, HostProtocol.ssh);
    expect(controller.sshHosts.single.port, 2222);
  });

  testWidgets('双协议卡片的 SSH、VNC 按钮分发不同连接动作', (tester) async {
    final actions = <HostAction>[];
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.build(Brightness.dark, AccentPreset.values.first),
        home: Scaffold(
          body: SizedBox(
            width: 340,
            height: 220,
            child: HostCard(host: dualHost, onAction: actions.add),
          ),
        ),
      ),
    );
    await tester.tap(find.byTooltip('连接 SSH 终端'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('连接 VNC 桌面'));
    await tester.pumpAndSettle();
    expect(actions, [HostAction.connectSsh, HostAction.connectVnc]);
    expect(find.text('SSH + VNC'), findsNothing);
    expect(find.text('SSH'), findsOneWidget);
    expect(find.text('VNC'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
  testWidgets('VNC 与 RDP 同时开启时使用不同图标及连接动作', (tester) async {
    final actions = <HostAction>[];
    final host = dualHost.copyWith(
      extra: {
        ...dualHost.extra,
        'connections': {
          'rdp': {'port': 3389, 'username': 'rdp-user'},
        },
      },
    );
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.build(Brightness.dark, AccentPreset.values.first),
        home: Scaffold(
          body: SizedBox(
            width: 340,
            height: 220,
            child: HostCard(host: host, onAction: actions.add),
          ),
        ),
      ),
    );
    await tester.tap(find.byTooltip('连接 VNC 桌面'));
    await tester.tap(find.byTooltip('连接 RDP 桌面'));
    expect(actions, [HostAction.connectVnc, HostAction.connectRdp]);
    expect(find.byIcon(Icons.desktop_windows_outlined), findsWidgets);
    expect(find.byIcon(Icons.window_rounded), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
  testWidgets('窗口放大再缩小时，视图切换始终靠右且筛选紧邻搜索框', (tester) async {
    final db = AppDatabase(NativeDatabase.memory());
    final controller = HostsController(HostRepository(db), GroupRepository(db));
    addTearDown(db.close);
    addTearDown(controller.dispose);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    tester.view.devicePixelRatio = 1;
    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: controller,
        child: MaterialApp(
          theme: AppTheme.build(Brightness.light, AccentPreset.values.first),
          home: const Scaffold(body: HostsPage()),
        ),
      ),
    );
    for (final width in [764.0, 1084.0, 1724.0, 2560.0, 3840.0, 764.0]) {
      tester.view.physicalSize = Size(width, 900);
      await tester.pump();
      final toggle = tester.getRect(find.byType(IconToggleGroup<bool>));
      final search = tester.getRect(find.byType(SearchField));
      final filters = tester.getRect(find.byType(PillChoice<ProtocolFilter>));
      expect(
        width - toggle.right,
        closeTo(24, 0.1),
        reason: '窗口宽度 $width 时保持右边距',
      );
      expect(filters.left - search.right, closeTo(16, 0.1));
      expect(search.width, lessThanOrEqualTo(360));
      expect(tester.takeException(), isNull);
    }
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
