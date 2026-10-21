import 'dart:io';

import 'package:desktop_drop/desktop_drop.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:remlark/ui_kit/file_drop_target.dart';

/// 模拟原生层发来的拖放事件：在 [at] 处进入、移动，然后松手放下文件
Future<void> _drop(WidgetTester tester, Offset at) async {
  // Windows 原生事件使用物理坐标，插件会按视图缩放转换为逻辑坐标。
  if (Platform.isWindows || Platform.isAndroid) {
    at *= tester.view.devicePixelRatio;
  }
  Future<void> send(String method, Object args) => tester.binding.defaultBinaryMessenger.handlePlatformMessage(
    'desktop_drop',
    const StandardMethodCodec().encodeMethodCall(MethodCall(method, args)),
    (_) {},
  );
  await send('entered', [at.dx, at.dy]);
  await send('updated', [at.dx, at.dy]);
  await send('performOperation', ['/tmp/a.txt']);
  await tester.pump();
}

/// 记录各区域收到的拖放
class _Log {
  final done = <String>[];
  final exited = <String>[];

  Widget target(String name, {bool raw = false}) {
    final child = ColoredBox(color: Colors.black, child: Text(name));
    if (raw) return DropTarget(onDragDone: (_) => done.add(name), child: child);
    return FileDropTarget(onDragDone: (_) => done.add(name), onDragExited: (_) => exited.add(name), child: child);
  }
}

/// 与工作区一致：会话叠放在同一位置，未显示的用 Visibility(maintainState) 隐藏
Widget _sessions(List<(Widget, bool)> sessions) => Stack(
  children: [
    for (final (w, visible) in sessions)
      Positioned.fill(
        child: Visibility(visible: visible, maintainState: true, child: w),
      ),
  ],
);

Widget _app(Widget child) => MaterialApp(home: Scaffold(body: child));

void main() {
  const center = Offset(400, 300);

  testWidgets('对照：原始 DropTarget 在隐藏会话中也会收到拖放（问题复现）', (tester) async {
    final log = _Log();
    await tester.pumpWidget(
      _app(_sessions([(log.target('rdp', raw: true), true), (log.target('ssh', raw: true), false)])),
    );
    await _drop(tester, center);
    expect(log.done, unorderedEquals(['rdp', 'ssh']));
  });

  testWidgets('RDP 与 SSH 叠放：只有显示的 RDP 收到', (tester) async {
    final log = _Log();
    await tester.pumpWidget(_app(_sessions([(log.target('rdp'), true), (log.target('ssh'), false)])));
    await _drop(tester, center);
    expect(log.done, ['rdp']);
  });

  testWidgets('多个 SSH 标签：只有当前显示的收到；切换后改由新标签收到', (tester) async {
    final log = _Log();
    Widget build(int active) => _app(_sessions([for (var i = 0; i < 3; i++) (log.target('ssh$i'), i == active)]));
    await tester.pumpWidget(build(1));
    await _drop(tester, center);
    expect(log.done, ['ssh1']);
    log.done.clear();
    await tester.pumpWidget(build(2));
    await _drop(tester, center);
    expect(log.done, ['ssh2']);
  });

  testWidgets('VNC、SFTP 与多个 SSH 混合：只有显示的 VNC 收到', (tester) async {
    final log = _Log();
    await tester.pumpWidget(
      _app(
        _sessions([
          (log.target('ssh1'), false),
          (log.target('vnc'), true),
          (log.target('sftp'), false),
          (log.target('ssh2'), false),
        ]),
      ),
    );
    await _drop(tester, center);
    expect(log.done, ['vnc']);
  });

  testWidgets('网格：各格只接收落在自己范围内的拖放，网格外隐藏的会话不接收', (tester) async {
    final log = _Log();
    await tester.pumpWidget(
      _app(
        Stack(
          children: [
            // 不在网格中的会话：全屏叠放且隐藏
            Positioned.fill(child: Visibility(visible: false, maintainState: true, child: log.target('hidden'))),
            Positioned(left: 0, top: 0, width: 390, height: 600, child: log.target('ssh')),
            Positioned(left: 410, top: 0, width: 390, height: 600, child: log.target('vnc')),
          ],
        ),
      ),
    );
    await _drop(tester, const Offset(100, 100));
    expect(log.done, ['ssh']);
    log.done.clear();
    await _drop(tester, const Offset(600, 100));
    expect(log.done, ['vnc']);
  });

  testWidgets('切到其他页面（IndexedStack）后，工作区中的会话不再接收', (tester) async {
    final log = _Log();
    Widget build(int page) => _app(
      IndexedStack(
        index: page,
        children: [
          const SizedBox.expand(),
          _sessions([(log.target('ssh'), true)]),
        ],
      ),
    );
    await tester.pumpWidget(build(0));
    await _drop(tester, center);
    expect(log.done, isEmpty);
    await tester.pumpWidget(build(1));
    await _drop(tester, center);
    expect(log.done, ['ssh']);
  });

  testWidgets('对话框打开时，下层会话不接收', (tester) async {
    final log = _Log();
    await tester.pumpWidget(_app(_sessions([(log.target('ssh'), true)])));
    showDialog<void>(
      context: tester.element(find.text('ssh')),
      builder: (_) => const AlertDialog(content: Text('dlg')),
    );
    await tester.pumpAndSettle();
    await _drop(tester, center);
    expect(log.done, isEmpty);
  });

  testWidgets('拖动中被隐藏时回调离开（拖放提示不残留）', (tester) async {
    final log = _Log();
    Widget build(bool visible) => _app(_sessions([(log.target('ssh'), visible)]));
    await tester.pumpWidget(build(true));
    await tester.binding.defaultBinaryMessenger.handlePlatformMessage(
      'desktop_drop',
      const StandardMethodCodec().encodeMethodCall(MethodCall('entered', [center.dx, center.dy])),
      (_) {},
    );
    await tester.pumpWidget(build(false));
    await tester.pump();
    expect(log.exited, ['ssh']);
  });
}
