import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:remlark/app/theme/app_palette.dart';
import 'package:remlark/app/theme/app_theme.dart';
import 'package:remlark/data/database.dart';
import 'package:remlark/l10n/app_localizations.dart';
import 'package:remlark/modules/hosts/group_repository.dart';
import 'package:remlark/modules/hosts/host_model.dart';
import 'package:remlark/modules/hosts/host_repository.dart';
import 'package:remlark/modules/hosts/hosts_controller.dart';
import 'package:remlark/modules/hosts/ui/host_editor_sections.dart';
import 'package:remlark/modules/hosts/ui/host_form.dart';
import 'package:remlark/modules/hosts/ui/jump_host_picker_dialog.dart';

import 'helpers/test_fonts.dart';

/// 构造测试主机，端点使用文档保留地址。
HostEntry _host(
  String id, {
  String? group,
  HostProtocol protocol = HostProtocol.ssh,
}) => HostEntry(
  uuid: id,
  name: id,
  protocol: protocol,
  groupUuid: group,
  address: '192.0.2.11',
  port: 2222,
  username: 'Admin',
  createdAt: 0,
  updatedAt: 0,
);

final _groups = [
  GroupEntry(uuid: 'prod', name: '生产环境', sortOrder: 0),
  GroupEntry(uuid: 'test', name: '测试环境', sortOrder: 1),
  GroupEntry(uuid: 'empty', name: '空分组', sortOrder: 2),
];

/// 使用真实主题及多语言代理渲染原生 Flutter 组件。
Widget _app(
  Widget body, {
  String locale = 'zh',
  Brightness brightness = Brightness.light,
}) => MaterialApp(
  debugShowCheckedModeBanner: false,
  locale: Locale(locale),
  supportedLocales: S.supportedLocales,
  localizationsDelegates: const [
    S.delegate,
    ...GlobalMaterialLocalizations.delegates,
  ],
  theme: AppTheme.build(brightness, AccentPreset.sage),
  home: Scaffold(body: body),
);

/// 覆盖分组与搜索组合、确认/取消、候选资格及大量数据的布局。
void main() {
  setUpAll(loadTestFonts);

  testWidgets('分组与搜索组合，切换筛选清除旧选择且无结果可恢复', (tester) async {
    await tester.pumpWidget(
      _app(
        JumpHostPickerDialog(
          candidates: [
            _host('HK-Bastion-01', group: 'prod'),
            _host('Test-Jump', group: 'test'),
            _host('Loose'),
          ],
          groups: _groups,
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(
      tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
      isNull,
    );
    await tester.tap(find.text('HK-Bastion-01'));
    await tester.pumpAndSettle();
    expect(
      tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
      isNotNull,
    );
    await tester.tap(find.text('测试环境'));
    await tester.pumpAndSettle();
    expect(find.text('HK-Bastion-01'), findsNothing);
    expect(find.text('Test-Jump'), findsOneWidget);
    expect(
      tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
      isNull,
    );
    await tester.enterText(find.byType(TextField), '  ADMIN@192.0.2.11:2222  ');
    await tester.pumpAndSettle();
    expect(find.text('Test-Jump'), findsOneWidget);
    await tester.enterText(find.byType(TextField), 'not-found');
    await tester.pumpAndSettle();
    expect(find.text('没有匹配的服务器，请调整搜索或分组。'), findsOneWidget);
    await tester.tap(find.byTooltip('清除搜索'));
    await tester.pumpAndSettle();
    expect(find.text('Test-Jump'), findsOneWidget);
    await tester.tap(find.text('未分组'));
    await tester.pumpAndSettle();
    expect(find.text('Loose'), findsOneWidget);
    expect(find.text('Test-Jump'), findsNothing);
    await tester.tap(find.text('空分组'));
    await tester.pumpAndSettle();
    expect(find.text('共 0 台'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('真实入口排除自身、已添加及非 SSH 主机，取消不修改，确认追加', (tester) async {
    final db = AppDatabase(NativeDatabase.memory());
    final hosts = HostsController(HostRepository(db), GroupRepository(db));
    final form = HostForm(_host('Self'), HostProtocol.ssh, null)
      ..jumpChain.add('Already');
    addTearDown(db.close);
    addTearDown(hosts.dispose);
    addTearDown(form.dispose);
    hosts.all.addAll([
      _host('Self'),
      _host('Already'),
      _host('Candidate'),
      _host('RDP', protocol: HostProtocol.rdp),
      _host('Dual', protocol: HostProtocol.vnc).copyWith(
        extra: {
          'ssh': {'enabled': true, 'port': 2200},
        },
      ),
    ]);
    hosts.selectedGroup = 'prod';
    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: hosts,
        child: _app(
          ListenableBuilder(
            listenable: form,
            builder: (_, _) => JumpChainSection(form: form),
          ),
        ),
      ),
    );
    await tester.tap(find.text('添加跳板服务器'));
    await tester.pumpAndSettle();
    expect(
      find.descendant(
        of: find.byType(JumpHostPickerDialog),
        matching: find.text('Self'),
      ),
      findsNothing,
    );
    expect(
      find.descendant(
        of: find.byType(JumpHostPickerDialog),
        matching: find.text('Already'),
      ),
      findsNothing,
    );
    expect(find.text('RDP'), findsNothing);
    expect(find.text('Admin@192.0.2.11:2200'), findsOneWidget);
    await tester.tap(find.text('Candidate'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    expect(form.jumpChain, ['Already']);
    await tester.tap(find.text('添加跳板服务器'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Candidate'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('添加到跳板链'));
    await tester.pumpAndSettle();
    expect(form.jumpChain, ['Already', 'Candidate']);
    expect(hosts.selectedGroup, 'prod');
    expect(find.byType(JumpHostPickerDialog), findsNothing);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('空候选有说明且无法确认，没有未分组候选时隐藏默认入口', (tester) async {
    await tester.pumpWidget(
      _app(JumpHostPickerDialog(candidates: const [], groups: _groups)),
    );
    await tester.pumpAndSettle();
    expect(find.text('暂无可添加的 SSH 服务器。'), findsOneWidget);
    expect(find.text('未分组'), findsNothing);
    expect(
      tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
      isNull,
    );
    await tester.pumpWidget(
      _app(
        JumpHostPickerDialog(
          candidates: [_host('Grouped', group: 'prod')],
          groups: _groups,
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('未分组'), findsNothing);
    // 用户创建的真实分组仍保留，只有系统提供的空“未分组”入口被隐藏。
    expect(find.text('空分组'), findsOneWidget);
  });

  testWidgets('中英文与深浅主题在最小桌面窗口容纳大量分组、主机及长名称', (tester) async {
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    tester.view.devicePixelRatio = 1;
    final candidates = List.generate(
      128,
      (i) => _host('Server-$i-very-long-name-for-overflow', group: 'group-$i'),
    );
    final groups = List.generate(
      60,
      (i) => GroupEntry(
        uuid: 'group-$i',
        name: '长分组名称 Long group name $i',
        sortOrder: i,
      ),
    );
    for (final locale in ['zh', 'en']) {
      for (final brightness in Brightness.values) {
        for (final size in [const Size(960, 640), const Size(1440, 900)]) {
          tester.view.physicalSize = size;
          await tester.pumpWidget(
            _app(
              JumpHostPickerDialog(candidates: candidates, groups: groups),
              locale: locale,
              brightness: brightness,
            ),
          );
          await tester.pumpAndSettle();
          expect(
            tester.takeException(),
            isNull,
            reason: '$locale $brightness $size',
          );
          final before = tester.getRect(find.byType(FilledButton));
          final hostList = find.descendant(
            of: find.byType(RadioGroup<String>),
            matching: find.byType(ListView),
          );
          await tester.drag(hostList, const Offset(0, -10000));
          await tester.pumpAndSettle();
          expect(tester.getRect(find.byType(FilledButton)), before);
          expect(
            find.byType(RadioListTile<String>).evaluate().length,
            lessThan(128),
          );
          await tester.pumpWidget(const SizedBox.shrink());
        }
      }
    }
  });

  // 按需生成真实组件截图，用于对照选定设计，不把生成图当作 UI 实现。
  testWidgets('方案一原生组件视觉截图', (tester) async {
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1200, 900);
    await tester.pumpWidget(
      RepaintBoundary(
        key: const ValueKey('preview'),
        child: _app(
          JumpHostPickerDialog(
            candidates: [
              for (var i = 1; i <= 16; i++)
                _host(
                  'HK-Bastion-${i.toString().padLeft(2, '0')}',
                  group: 'prod',
                ),
            ],
            groups: _groups,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('生产环境'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('HK-Bastion-01'));
    await tester.pumpAndSettle();
    await expectLater(
      find.byKey(const ValueKey('preview')),
      matchesGoldenFile('../build/validation/jump-picker/implementation.png'),
    );
  }, skip: Platform.environment['JUMP_PICKER_SNAPSHOT'] != '1');
}
