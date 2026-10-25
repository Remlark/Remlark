import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:remlark/app/app.dart';
import 'package:remlark/app/nav_controller.dart';
import 'package:remlark/l10n/app_localizations.dart';
import 'package:remlark/modules/hosts/host_model.dart';
import 'package:remlark/modules/remote_desktop/ui/vnc_view.dart';
import 'package:remlark/modules/workspace/ui/workspace_actions.dart';
import 'package:remlark/modules/workspace/workspace_tab.dart';

import 'package:remlark/utils/secret_store.dart';

import 'utils/workspace_test_utils.dart';

/// 从真实布局菜单切换模式，检查画布位置与会话视图身份。
void main() {
  for (final locale in ['zh', 'en']) {
    testWidgets('$locale 布局菜单切单页、关闭新开、恢复两列网格且保留视图', (tester) async {
      final s = fixture();
      final w = s.workspace;
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(1440, 900);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);
      SecretStore.initForTest(Uint8List(32));
      await tester.runAsync(() async {
        await s.init(installKeySnippetName: 'SSH');
        await s.settings.setLocale(Locale(locale));
      });
      addTearDown(s.updates.dispose);
      final a = open(s, HostProtocol.vnc, 'a')
        ..state = SessionState.disconnected;
      final b = open(s, HostProtocol.vnc, 'b')
        ..state = SessionState.disconnected;
      await tester.pumpWidget(RemlarkApp(services: s));
      tester
          .element(find.byType(Scaffold).first)
          .read<NavController>()
          .go(AppPage.sessions);
      await tester.pumpAndSettle();
      final context = tester.element(find.byType(WorkspaceActions));
      final translations = S.of(context);

      /// 点击真实菜单项，避免只调用控制器掩盖界面刷新问题。
      Future<void> layout(String key) async {
        await tester.tap(find.byKey(const ValueKey('workspace-layout')));
        await tester.pumpAndSettle();
        await tester.tap(find.text(translations.t(key)).last);
        await tester.pumpAndSettle();
      }

      /// 获取带固定身份的实际会话画布区域。
      Finder tile(String id) => find.byKey(ValueKey('session-$id'));

      await layout('workspace.layout.grid');
      expect(find.byKey(ValueKey('grid-header-${a.id}')), findsOneWidget);
      expect(find.byKey(ValueKey('grid-header-${b.id}')), findsOneWidget);
      final view = find.descendant(
        of: tile(b.id),
        matching: find.byType(VncView),
      );
      final originalState = tester.state(view);
      await layout('workspace.layout.single');
      await tester.runAsync(() => w.closeTab(a));
      final c = open(s, HostProtocol.vnc, 'c')
        ..state = SessionState.disconnected;
      await tester.pumpAndSettle();
      await layout('workspace.layout.grid');
      expect(find.byKey(ValueKey('grid-header-${b.id}')), findsOneWidget);
      expect(find.byKey(ValueKey('grid-header-${c.id}')), findsOneWidget);
      final left = tester.getRect(tile(b.id));
      final right = tester.getRect(tile(c.id));
      expect(left.right, lessThan(right.left));
      expect(left.top, right.top);
      expect(left.width, right.width);
      expect(tester.state(view), same(originalState));
      // 实际点击聚焦和返回入口，验证布局与内容仍保持一致。
      final header = find.byKey(ValueKey('grid-header-${b.id}'));
      await tester.tap(
        find.descendant(
          of: header,
          matching: find.byIcon(Icons.open_in_full_rounded),
        ),
      );
      await tester.pumpAndSettle();
      // 标题栏还支持双击，等待单击手势仲裁窗口结束。
      await tester.pump(const Duration(milliseconds: 350));
      await tester.pumpAndSettle();
      expect(w.focusedGridId, b.id);
      expect(tester.getSize(tile(b.id)).width, greaterThan(left.width));
      await tester.tap(find.text(translations.t('workspace.grid.return')));
      await tester.pumpAndSettle();
      expect(tester.getRect(tile(b.id)), left);
      expect(tester.state(view), same(originalState));
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }
}
