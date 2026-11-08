// SFTP 双栏拖动：放下时由来源栏执行传输、多文件拖动、拖动提示跟随指针、离开窗口交给系统拖动
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:remlark/app/theme/app_palette.dart';
import 'package:remlark/app/theme/app_theme.dart';
import 'package:remlark/l10n/app_localizations.dart';
import 'package:remlark/modules/sftp/file_source.dart';
import 'package:remlark/modules/sftp/sftp_service.dart';
import 'package:remlark/modules/sftp/ui/file_pane.dart';

/// 固定文件列表的文件来源
class _FakeSource implements FileSource {
  _FakeSource(this.isRemote, this.files);

  @override
  final bool isRemote;
  final List<String> files;

  @override
  Future<String> home() async => '/h';
  @override
  Future<List<FileEntry>> list(String path) async => [
    for (final f in files) FileEntry(name: f, path: '/h/$f', isDir: false, isLink: false, size: 10),
  ];
  @override
  Future<void> mkdir(String path) async {}
  @override
  Future<void> rename(String from, String to) async {}
  @override
  Future<void> delete(FileEntry f) async {}
  @override
  String join(String dir, String name) => '$dir/$name';
  @override
  String parent(String path) => path;
}

/// 两栏各自收到的传输与拖出请求
class _Calls {
  final List<List<String>> local = [];
  final List<List<String>> remote = [];
  final List<List<String>> dragOut = [];
}

const _window = Size(1400, 700);

/// 左侧本地栏、右侧远程栏；[dragOutResult] 为 null 时远程栏不支持拖出
Future<_Calls> _pump(WidgetTester tester, {bool? dragOutResult}) async {
  await tester.binding.setSurfaceSize(_window);
  addTearDown(() => tester.binding.setSurfaceSize(null));
  final calls = _Calls();
  Widget pane(bool remote, List<String> files) => Expanded(
    child: FilePane(
      source: _FakeSource(remote, files),
      title: remote ? 'R' : 'L',
      icon: Icons.folder,
      transferLabel: 'T',
      transferIcon: Icons.upload,
      onTransfer: (f) => (remote ? calls.remote : calls.local).add([for (final e in f) e.name]),
      onPathChanged: (_) {},
      onDragOut: remote && dragOutResult != null
          ? (f) async {
              calls.dragOut.add([for (final e in f) e.name]);
              return dragOutResult;
            }
          : null,
    ),
  );
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.build(Brightness.light, AccentPreset.values.first),
      localizationsDelegates: const [S.delegate],
      home: Scaffold(
        body: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            pane(false, ['a.txt', 'b.txt', 'c.txt']),
            pane(true, ['r1.log', 'r2.log']),
          ],
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return calls;
}

/// 鼠标从 [from] 分步移动到 [to] 后松开；[beforeUp] 在松开前执行检查
Future<void> _drag(WidgetTester tester, Offset from, Offset to, {Future<void> Function()? beforeUp}) async {
  final g = await tester.startGesture(from, kind: PointerDeviceKind.mouse);
  await tester.pump();
  const steps = 10;
  for (var i = 1; i <= steps; i++) {
    await g.moveTo(Offset.lerp(from, to, i / steps)!);
    await tester.pump();
  }
  await beforeUp?.call();
  await g.up();
  await tester.pumpAndSettle();
}

/// 文件名所在行的中心
Offset _row(WidgetTester tester, String name) => tester.getCenter(find.text(name));

/// 目标栏内的空白位置
Offset _paneOf(WidgetTester tester, String name) => tester.getCenter(find.text(name)) + const Offset(0, 160);

void main() {
  testWidgets('本地文件拖到远程栏：由本地栏执行上传，远程栏不执行下载', (tester) async {
    final calls = await _pump(tester);
    await _drag(tester, _row(tester, 'a.txt'), _paneOf(tester, 'r1.log'));
    expect(calls.local, [
      ['a.txt'],
    ]);
    expect(calls.remote, isEmpty);
  });

  testWidgets('远程文件拖到本地栏：由远程栏执行下载', (tester) async {
    final calls = await _pump(tester);
    await _drag(tester, _row(tester, 'r2.log'), _paneOf(tester, 'a.txt'));
    expect(calls.remote, [
      ['r2.log'],
    ]);
    expect(calls.local, isEmpty);
  });

  testWidgets('同栏内拖动不触发传输', (tester) async {
    final calls = await _pump(tester);
    await _drag(tester, _row(tester, 'a.txt'), _row(tester, 'c.txt'));
    expect(calls.local, isEmpty);
    expect(calls.remote, isEmpty);
  });

  testWidgets('拖动已选中的多个文件时一起传输，提示显示数量', (tester) async {
    final calls = await _pump(tester);
    await tester.tap(find.text('a.txt'));
    await tester.pump(const Duration(milliseconds: 400));
    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await tester.tap(find.text('c.txt'));
    // 行同时支持双击，单击在双击等待结束后才回调，此时 Shift 仍需按住
    await tester.pump(const Duration(milliseconds: 400));
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    await _drag(
      tester,
      _row(tester, 'b.txt'),
      _paneOf(tester, 'r1.log'),
      beforeUp: () async => expect(find.textContaining('3 '), findsOneWidget),
    );
    expect(calls.local, [
      ['a.txt', 'b.txt', 'c.txt'],
    ]);
  });

  testWidgets('从行内任意位置开始拖动，提示都紧跟指针', (tester) async {
    await _pump(tester);
    // 从文件名右侧的空白处开始拖动（对应截图中绿色框的位置）
    final start = _row(tester, 'a.txt') + const Offset(260, 0);
    final end = Offset(start.dx + 300, start.dy + 120);
    await _drag(
      tester,
      start,
      end,
      beforeUp: () async {
        final feedback = tester.getRect(find.byType(Material).last);
        expect((feedback.left - end.dx).abs(), lessThan(20));
        expect((feedback.top - end.dy).abs(), lessThan(20));
      },
    );
  });

  testWidgets('远程文件拖出窗口：只交给系统拖动一次并隐藏应用内提示', (tester) async {
    final calls = await _pump(tester, dragOutResult: true);
    final start = _row(tester, 'r1.log');
    await _drag(
      tester,
      start,
      Offset(_window.width + 40, start.dy),
      beforeUp: () async {
        final opacity = tester.widget<Opacity>(find.byType(Opacity).last);
        expect(opacity.opacity, 0);
      },
    );
    expect(calls.dragOut, [
      ['r1.log'],
    ]);
    expect(calls.local, isEmpty);
  });

  testWidgets('系统拖动未能开始时恢复应用内提示', (tester) async {
    final calls = await _pump(tester, dragOutResult: false);
    final start = _row(tester, 'r1.log');
    await _drag(
      tester,
      start,
      Offset(_window.width + 40, start.dy),
      beforeUp: () async {
        final opacity = tester.widget<Opacity>(find.byType(Opacity).last);
        expect(opacity.opacity, 1);
      },
    );
    expect(calls.dragOut, isNotEmpty);
  });

  testWidgets('本地栏没有拖出：拖到窗口外不调用', (tester) async {
    final calls = await _pump(tester, dragOutResult: true);
    final start = _row(tester, 'a.txt');
    await _drag(tester, start, Offset(-30, start.dy));
    expect(calls.dragOut, isEmpty);
  });

  test('窗口边缘判断', () {
    const w = Size(100, 80);
    expect(isOutsideWindow(const Offset(50, 40), w), isFalse);
    expect(isOutsideWindow(const Offset(0, 40), w), isTrue);
    expect(isOutsideWindow(const Offset(-5, 40), w), isTrue);
    expect(isOutsideWindow(const Offset(99.5, 40), w), isTrue);
    expect(isOutsideWindow(const Offset(50, 85), w), isTrue);
  });
}
