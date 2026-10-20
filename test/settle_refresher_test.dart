import 'package:flutter_test/flutter_test.dart';
import 'package:remlark/modules/remote_desktop/vnc/settle_refresher.dart';

void main() {
  const w = 1920, h = 1080;
  Future<void> wait(int ms) => Future.delayed(Duration(milliseconds: ms));

  SettleRefresher make(List<List<(int, int, int, int)>> calls) => SettleRefresher(
    refresh: calls.add,
    quiet: const Duration(milliseconds: 60),
    inputQuiet: const Duration(milliseconds: 10),
    inputWindow: const Duration(milliseconds: 200),
    guard: const Duration(milliseconds: 300),
  );

  test('画面静止后对变化区域（外扩）补刷新一次', () async {
    final calls = <List<(int, int, int, int)>>[];
    final s = make(calls);
    s.noteChanges([(100, 100, 50, 20)], w, h);
    await wait(20);
    s.noteChanges([(300, 100, 10, 10)], w, h);
    await wait(30);
    expect(calls, isEmpty, reason: '仍在变化，不应补刷新');
    await wait(80);
    expect(calls, [
      [(84, 84, 82, 52), (284, 84, 42, 42)],
    ]);
    s.dispose();
  });

  test('相交的区域合并为外接矩形后补刷新', () async {
    final calls = <List<(int, int, int, int)>>[];
    final s = make(calls);
    // 高亮行与其上弹出的菜单
    s.noteChanges([(200, 100, 800, 20), (500, 110, 300, 400)], w, h);
    await wait(100);
    expect(calls, [
      [(184, 84, 832, 442)],
    ]);
    s.dispose();
  });

  test('补刷新的结果不会再次触发补刷新，区域外的新变化照常处理', () async {
    final calls = <List<(int, int, int, int)>>[];
    final s = make(calls);
    s.noteChanges([(100, 100, 50, 20)], w, h);
    await wait(100);
    expect(calls.length, 1);
    // 补刷新返回的区域（可能被服务端拆成多块）
    s.noteChanges([(84, 84, 82, 26), (84, 110, 82, 26)], w, h);
    await wait(100);
    expect(calls.length, 1);
    s.noteChanges([(1000, 500, 10, 10)], w, h);
    await wait(100);
    expect(calls.length, 2);
    s.dispose();
  });

  test('输入后等待更短；大面积变化改为整屏', () async {
    final calls = <List<(int, int, int, int)>>[];
    final s = make(calls);
    s.noteInput();
    s.noteChanges([(0, 0, 1500, 900)], w, h);
    await wait(30);
    expect(calls, [
      [(0, 0, w, h)],
    ]);
    s.dispose();
  });
}
