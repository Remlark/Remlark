import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:remlark/modules/hosts/host_model.dart';
import 'package:remlark/modules/workspace/workspace_controller.dart';

import 'utils/workspace_test_utils.dart';

/// 每步检查可见会话、输入焦点、选择有效性和容量，不依赖具体实现分支。
void checkState(WorkspaceController w, String trace) {
  final ids = w.tabs.map((t) => t.id).toSet();
  final candidates = w.gridCandidates.map((t) => t.id).toSet();
  expect(w.gridIds.toSet().length, w.gridIds.length, reason: trace);
  expect(w.broadcastIds.toSet().length, w.broadcastIds.length, reason: trace);
  expect(w.gridIds.length, lessThanOrEqualTo(9), reason: trace);
  expect(w.broadcastIds.length, lessThanOrEqualTo(9), reason: trace);
  expect(candidates.containsAll(w.gridIds), isTrue, reason: trace);
  expect(
    w.terminals.map((t) => t.id).toSet().containsAll(w.broadcastIds),
    isTrue,
    reason: trace,
  );
  expect(
    w.activeId == null ? ids.isEmpty : ids.contains(w.activeId),
    isTrue,
    reason: trace,
  );
  if (w.gridEnabled) expect(w.gridIds, isNotEmpty, reason: trace);
  if (w.focusedGridId != null) {
    expect(w.gridEnabled, isTrue, reason: trace);
    expect(ids, contains(w.focusedGridId), reason: trace);
    if (!w.broadcast) expect(w.activeId, w.focusedGridId, reason: trace);
  }
  if (w.showingGrid) {
    expect(w.displayedGridSessions, isNotEmpty, reason: trace);
    expect(
      w.displayedGridSessions.map((t) => t.id),
      contains(w.activeId),
      reason: trace,
    );
  }
  if (w.broadcast) expect(w.broadcastIds, isNotEmpty, reason: trace);
  if (ids.isEmpty) expect(w.showingStartPage, isTrue, reason: trace);
}

/// 覆盖明确的行为矩阵与可复现的长操作序列。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  for (final protocol in HostProtocol.values) {
    for (final mode in ['single', 'grid', 'focus', 'broadcast']) {
      for (final closeActive in [false, true]) {
        test(
          '$protocol / $mode / 关闭${closeActive ? '活动' : '非活动'}会话后新增',
          () async {
            final s = fixture();
            final w = s.workspace;
            final a = open(s, HostProtocol.ssh, 'a');
            final b = open(s, HostProtocol.ssh, 'b');
            w.showGrid([a.id, b.id]);
            w.selectTab(b.id);
            switch (mode) {
              case 'single':
                w.showSingle();
              case 'focus':
                w.focusGridSession(b.id);
              case 'broadcast':
                w.startBroadcast(ids: [a.id, b.id]);
            }
            await w.closeTab(closeActive ? b : a);
            checkState(w, '关闭后');
            final remaining = closeActive ? a : b;
            final previousGrid = List.of(w.gridIds);
            final newTab = open(s, protocol, 'new');
            checkState(w, '新增后');
            if (mode == 'broadcast') {
              expect(w.gridIds, previousGrid);
              expect(w.broadcastIds, [remaining.id]);
              w.stopBroadcast();
            } else if (mode != 'focus' || closeActive) {
              expect(w.gridIds, [remaining.id, newTab.id]);
            } else {
              expect(w.focusedGridId, newTab.id);
              expect(w.gridIds, previousGrid);
            }
            w.showGrid();
            expect(w.showingGrid, isTrue);
            checkState(w, '恢复后');
          },
        );
      }
    }
  }

  for (final exit in ['stop', 'remove', 'close']) {
    test('聚焦远程桌面后广播，通过 $exit 结束时恢复原聚焦', () async {
      final s = fixture();
      final w = s.workspace;
      final ssh = open(s, HostProtocol.ssh, 'ssh');
      final desktop = open(s, HostProtocol.rdp, 'desktop');
      w.showGrid();
      w.focusGridSession(desktop.id);
      w.startBroadcast(ids: [ssh.id]);
      switch (exit) {
        case 'stop':
          w.stopBroadcast();
        case 'remove':
          w.removeFromBroadcast(ssh.id);
        case 'close':
          await w.closeTab(ssh);
      }
      expect(w.active, desktop);
      expect(w.focusedGridId, desktop.id);
      checkState(w, exit);
    });
  }

  test('广播中关闭原聚焦会话后，停止广播恢复剩余网格', () async {
    final s = fixture();
    final w = s.workspace;
    final a = open(s, HostProtocol.ssh, 'a');
    final b = open(s, HostProtocol.ssh, 'b');
    w.showGrid();
    w.focusGridSession(a.id);
    w.startBroadcast(ids: [b.id]);
    await w.closeTab(a);
    w.stopBroadcast();
    expect(w.focusedGridId, isNull);
    expect(w.displayedGridSessions, [b]);
    checkState(w, '关闭原聚焦');
  });

  test('所有激活入口遵守网格聚焦和广播可见范围', () {
    final s = fixture();
    final w = s.workspace;
    final a = open(s, HostProtocol.ssh, 'a');
    final b = open(s, HostProtocol.ssh, 'b');
    w.showGrid([a.id]);
    w.activate(b.id);
    expect(w.focusedGridId, b.id);
    checkState(w, '直接激活网格外标签');
    w.startBroadcast(ids: [a.id]);
    w.activate(b.id);
    expect(w.active, a);
    checkState(w, '广播中激活非目标');
  });

  test('SFTP 复用、返回终端、关闭父会话与空工作区重开', () async {
    final s = fixture();
    final w = s.workspace;
    final a = open(s, HostProtocol.ssh, 'a') as RecordingTerminal;
    final b = open(s, HostProtocol.ssh, 'b');
    w.showGrid();
    final files = w.openSftp(a);
    expect(w.openSftp(a), same(files));
    expect(w.tabs.length, 3);
    w.activate(a.id);
    expect(w.focusedGridId, a.id);
    checkState(w, '文件页返回终端');
    w.openSftp(a);
    await w.closeTab(a);
    expect(w.tabs, [b]);
    expect(w.showingGrid, isTrue);
    await w.closeAll();
    checkState(w, '全部关闭');
    final c = open(s, HostProtocol.vnc, 'c');
    final d = open(s, HostProtocol.rdp, 'd');
    w.showGrid();
    expect(w.displayedGridSessions, [c, d]);
  });

  test('空选择无副作用，重复和失效 ID 被过滤，广播只接受 SSH 且最多九个', () {
    final s = fixture();
    final w = s.workspace;
    expect(w.showGrid(), isFalse);
    expect(w.startBroadcast(), isFalse);
    final ssh = List.generate(11, (i) => open(s, HostProtocol.ssh, '$i'));
    final desktop = open(s, HostProtocol.vnc, 'vnc');
    w.showGrid([ssh[1].id, ssh[0].id, ssh[1].id, 'missing']);
    expect(w.gridIds, [ssh[1].id, ssh[0].id]);
    expect(w.showGrid([]), isFalse);
    expect(w.gridIds, [ssh[1].id, ssh[0].id]);
    w.startBroadcast(ids: [desktop.id, ...ssh.map((t) => t.id), ssh[0].id]);
    expect(w.broadcastIds, ssh.take(9).map((t) => t.id).toList());
    expect(w.addToBroadcast(ssh.last.id), isFalse);
    expect(w.startBroadcast(ids: ['missing']), isFalse);
    expect(w.broadcastIds.length, 9);
    w.showSingle();
    w.focusGridSession(ssh[0].id);
    expect(w.showGrid([desktop.id]), isFalse);
    checkState(w, '无效操作与容量');
  });

  for (var count = 0; count <= 12; count++) {
    for (final single in [false, true]) {
      test('容量边界 $count 个会话，${single ? '单页保存' : '网格'}期间新增', () async {
        final s = fixture();
        final w = s.workspace;
        final tabs = List.generate(
          count,
          (i) => open(s, HostProtocol.values[i % 3], 'session-$i'),
        );
        expect(w.showGrid(), count > 0);
        if (single) w.showSingle();
        final newTab = open(s, HostProtocol.ssh, 'new');
        checkState(w, '新增后');
        if (count >= 9 && !single) {
          expect(w.focusedGridId, newTab.id);
          expect(w.active, newTab);
        }
        w.showGrid();
        expect(w.gridIds.length, min(count + 1, 9));
        expect(w.gridIds.contains(newTab.id), count < 9);
        if (count >= 9) {
          // 满格关闭一项后再新增可以补位，不自动吸收之前被排除的会话。
          await w.closeTab(tabs.first);
          final replacement = open(s, HostProtocol.rdp, 'replacement');
          expect(w.gridIds.last, replacement.id);
          expect(w.gridIds.length, 9);
          expect(w.gridIds, isNot(contains(newTab.id)));
        }
        checkState(w, '容量恢复后');
      });
    }
  }

  test('开始页取消保留聚焦，非法选择不通知，切回同一标签仍退出开始页', () {
    final s = fixture();
    final w = s.workspace;
    final a = open(s, HostProtocol.ssh, 'a');
    w.showGrid();
    w.focusGridSession(a.id);
    var notifications = 0;
    w.addListener(() => notifications++);
    w.selectTab('missing');
    w.focusGridSession('missing');
    expect(w.showGrid(['missing']), isFalse);
    expect(notifications, 0);
    w.showStartPage();
    w.resumeSessions();
    expect(w.focusedGridId, a.id);
    w.showStartPage();
    w.selectTab(a.id);
    expect(w.showingStartPage, isFalse);
    expect(w.active, a);
    checkState(w, '开始页往返');
  });

  for (final broadcasting in [false, true]) {
    test('拖动标签顺序必定通知，广播=$broadcasting 时遵守焦点限制', () {
      final s = fixture();
      final w = s.workspace;
      final a = open(s, HostProtocol.ssh, 'a');
      final b = open(s, HostProtocol.ssh, 'b');
      w.showGrid([a.id]);
      if (broadcasting) {
        w.startBroadcast(ids: [a.id]);
      } else {
        w.selectTab(b.id);
      }
      var notifications = 0;
      w.addListener(() => notifications++);
      w.reorderTab(1, 0);
      expect(w.tabs, [b, a]);
      expect(w.gridIds, [a.id]);
      expect(w.active, broadcasting ? a : b);
      expect(notifications, greaterThan(0));
      checkState(w, '标签拖动');
    });
  }

  for (final seed in [7, 23, 101, 2026]) {
    test('随机状态序列 seed=$seed，400 步逐步验证', () async {
      final s = fixture();
      final w = s.workspace;
      final random = Random(seed);
      final trace = <String>[];
      for (var step = 0; step < 400; step++) {
        final op = random.nextInt(15);
        final tab = w.tabs.isEmpty
            ? null
            : w.tabs[random.nextInt(w.tabs.length)];
        trace.add('$step:$op:${tab?.title}');
        switch (op) {
          case 0:
          case 1:
            if (w.tabs.length < 14) {
              open(s, HostProtocol.values[random.nextInt(3)], 'new-$step');
            }
          case 2:
            if (tab != null) await w.closeTab(tab);
          case 3:
            w.showGrid();
          case 4:
            w.showSingle();
          case 5:
            if (tab != null) w.focusGridSession(tab.id);
          case 6:
            if (tab != null) w.selectTab(tab.id);
          case 7:
            w.startBroadcast();
          case 8:
            w.stopBroadcast();
          case 9:
            w.showStartPage();
          case 10:
            w.resumeSessions();
          case 11:
            if (tab is RecordingTerminal) w.openSftp(tab);
          case 12:
            if (tab != null) w.activate(tab.id);
          case 14:
            if (w.tabs.isNotEmpty) w.reorderTab(0, w.tabs.length - 1);
          case 13:
            if (tab != null) w.removeFromBroadcast(tab.id);
        }
        checkState(w, 'seed=$seed ${trace.join(",")}');
      }
    });
  }
}
