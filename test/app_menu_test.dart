// 统一菜单控件：无动画、下拉对齐与等宽、右键菜单位置翻转、选择框取值
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:remlark/app/theme/app_palette.dart';
import 'package:remlark/app/theme/app_theme.dart';
import 'package:remlark/ui_kit/app_menu.dart';

/// 菜单面板（以第一个菜单项向上找到的 Material）
Rect _panelRect(WidgetTester tester, String itemText) {
  final material = find.ancestor(of: find.text(itemText), matching: find.byType(Material)).first;
  return tester.getRect(material);
}

Widget _app(Widget child) => MaterialApp(
  theme: AppTheme.build(Brightness.light, AccentPreset.values.first),
  home: Scaffold(body: child),
);

void main() {
  testWidgets('下拉选择框：一帧内出现、与选择框等宽且左对齐在下方，选中后回调', (tester) async {
    String? value = 'a';
    await tester.binding.setSurfaceSize(const Size(800, 600));
    await tester.pumpWidget(
      _app(
        StatefulBuilder(
          builder: (context, setState) => Align(
            alignment: Alignment.topLeft,
            child: Padding(
              padding: const EdgeInsets.only(left: 100, top: 50),
              child: SizedBox(
                width: 240,
                child: AppDropdown<String>(
                  key: const ValueKey('dd'),
                  value: value,
                  items: const [
                    AppMenuItem(value: 'a', label: 'Alpha'),
                    AppMenuItem(value: 'b', label: 'Beta'),
                  ],
                  onChanged: (v) => setState(() => value = v),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    final field = tester.getRect(find.byKey(const ValueKey('dd')));
    await tester.tap(find.byKey(const ValueKey('dd')));
    // 只推进一帧：没有动画，菜单应已完整显示
    await tester.pump();
    expect(find.text('Beta'), findsOneWidget);
    final panel = _panelRect(tester, 'Beta');
    expect(panel.width, field.width);
    expect(panel.left, field.left);
    expect(panel.top, greaterThanOrEqualTo(field.bottom));
    await tester.tap(find.text('Beta'));
    await tester.pump();
    expect(value, 'b');
    expect(find.text('Alpha'), findsNothing);
  });

  testWidgets('右键菜单：在鼠标处出现，靠近右下角时向左上翻转，点击外部关闭', (tester) async {
    await tester.binding.setSurfaceSize(const Size(800, 600));
    late BuildContext ctx;
    await tester.pumpWidget(
      _app(
        Builder(
          builder: (context) {
            ctx = context;
            return const SizedBox.expand();
          },
        ),
      ),
    );
    final items = [
      const AppMenuItem(value: 1, label: 'One'),
      const AppMenuDivider<int>(),
      const AppMenuItem(value: 2, label: 'Two'),
    ];

    AppMenu.showAt<int>(ctx, const Offset(200, 150), items);
    await tester.pump();
    var panel = _panelRect(tester, 'One');
    expect(panel.topLeft, const Offset(200, 150));
    expect(panel.width, greaterThanOrEqualTo(180));

    // 点击菜单外关闭
    await tester.tapAt(const Offset(10, 10));
    await tester.pump();
    expect(find.text('One'), findsNothing);

    AppMenu.showAt<int>(ctx, const Offset(790, 590), items);
    await tester.pump();
    panel = _panelRect(tester, 'One');
    expect(panel.right, 790);
    expect(panel.bottom, 590);
  });

  testWidgets('按钮下拉：宽度不小于按钮，菜单项回调在关闭后执行', (tester) async {
    await tester.binding.setSurfaceSize(const Size(800, 600));
    var tapped = 0;
    await tester.pumpWidget(
      _app(
        Center(
          child: AppMenuAnchor<void>(
            builder: (context, open) => SizedBox(
              key: const ValueKey('btn'),
              width: 260,
              height: 36,
              child: TextButton(onPressed: open, child: const Text('Open')),
            ),
            items: (context) => [AppMenuItem(label: 'Do', onTap: () => tapped++)],
          ),
        ),
      ),
    );
    final btn = tester.getRect(find.byKey(const ValueKey('btn')));
    await tester.tap(find.text('Open'));
    await tester.pump();
    final panel = _panelRect(tester, 'Do');
    expect(panel.width, greaterThanOrEqualTo(btn.width));
    expect(panel.left, btn.left);
    expect(panel.top, btn.bottom + 4);
    await tester.tap(find.text('Do'));
    await tester.pump();
    expect(tapped, 1);
    expect(find.text('Do'), findsNothing);
    // 确认主题扩展可用（菜单使用 palette 着色）
    expect(Theme.of(tester.element(find.text('Open'))).extension<AppPalette>(), isNotNull);
  });
}
