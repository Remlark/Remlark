import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:remlark/app/app_services.dart';
import 'package:remlark/data/database.dart';
import 'package:remlark/modules/hosts/host_model.dart';
import 'package:remlark/modules/remote_desktop/vnc/vnc_session.dart';
import 'package:remlark/modules/ssh/ssh_connector.dart';
import 'package:remlark/modules/ssh/ui/ssh_dialogs.dart';
import 'package:remlark/modules/terminal/terminal_session.dart';

/// 记录广播输入，不发起网络连接。
class RecordingTerminal extends TerminalSession {
  RecordingTerminal(HostEntry host, SshConnector connector)
    : super(host, connector, DialogInteraction());
  final received = <String>[];
  @override
  void sendRaw(String data) => received.add(data);
}

/// 生成无需保存到数据库的会话主机。
HostEntry host(String name, [HostProtocol protocol = HostProtocol.ssh]) =>
    HostEntry(
      uuid: name,
      name: name,
      protocol: protocol,
      address: 'localhost',
      port: protocol.defaultPort,
      username: 'test',
      createdAt: 0,
      updatedAt: 0,
    );

/// 验证布局和广播状态独立，且输入只到明确选中的 SSH 目标。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('混合网格聚焦恢复、广播隔离、新会话及关闭清理', () async {
    final db = AppDatabase(NativeDatabase.memory());
    final services = AppServices(db);
    final w = services.workspace;
    final a = RecordingTerminal(host('a'), services.connector);
    final b = RecordingTerminal(host('b'), services.connector);
    final c = RecordingTerminal(host('c'), services.connector);
    final ui = DialogInteraction();
    final desktop = VncSession(
      host('mac', HostProtocol.vnc),
      services.hostRepo,
      services.connector,
      ui,
      ui,
    );
    for (final tab in [a, b, c, desktop]) {
      w.add(tab);
    }
    // 新建会话是展示状态：重复打开不会创建标签，点击原活动标签可返回。
    w.showStartPage();
    w.showStartPage();
    expect(w.showingStartPage, isTrue);
    expect(w.tabs.length, 4);
    w.selectTab(desktop.id);
    expect(w.showingStartPage, isFalse);
    final files = w.openSftp(a);
    expect(w.showGrid([a.id, b.id, desktop.id, files.id, 'missing']), isTrue);
    expect(w.gridIds, [a.id, b.id, desktop.id]);
    w.focusGridSession(desktop.id);
    expect(w.active, desktop);
    expect(w.showingGrid, isFalse);
    w.returnToGrid();
    expect(w.showingGrid, isTrue);
    a.onUserInput!(a, 'local');
    expect(b.received, isEmpty);
    expect(w.startBroadcast(ids: [a.id, b.id, desktop.id]), isTrue);
    expect(w.broadcastIds, [a.id, b.id]);
    w.showStartPage();
    expect(w.broadcast, isTrue);
    expect(w.broadcastIds, [a.id, b.id]);
    expect(w.gridIds, [a.id, b.id, desktop.id]);
    w.resumeSessions();
    expect(w.showingStartPage, isFalse);
    expect(w.showingGrid, isTrue);
    a.onUserInput!(a, 'selected');
    c.onUserInput!(c, 'excluded');
    expect(b.received, ['selected']);
    expect(a.received, isEmpty);
    expect(c.received, isEmpty);
    expect(w.showGrid([desktop.id]), isFalse);
    w.showSingle();
    w.focusGridSession(a.id);
    expect(w.showingGrid, isTrue);
    final d = RecordingTerminal(host('new'), services.connector);
    w.showStartPage();
    w.add(d);
    expect(w.showingStartPage, isFalse);
    expect(w.broadcastIds, [a.id, b.id]);
    expect(w.gridIds, [a.id, b.id, desktop.id]);
    w.stopBroadcast();
    expect(w.showingGrid, isTrue);
    a.onUserInput!(a, 'stopped');
    expect(b.received, ['selected']);
    // 单窗口下开启广播也以网格展示广播目标，停止后恢复单窗口
    w.showSingle();
    expect(w.showingGrid, isFalse);
    w.activate(c.id);
    w.startBroadcast(ids: [a.id, b.id]);
    expect(w.showingGrid, isTrue);
    expect(w.displayedGridSessions, [a, b]);
    expect(w.active, a);
    w.selectTab(c.id);
    expect(w.active, a);
    w.selectTab(b.id);
    expect(w.active, b);
    w.stopBroadcast();
    expect(w.showingGrid, isFalse);
    expect(w.gridEnabled, isFalse);
    w.showGrid();
    w.startBroadcast(ids: [b.id]);
    await w.closeTab(b);
    expect(w.broadcast, isFalse);
    expect(w.gridIds, [a.id, desktop.id]);
    await w.closeAll();
    expect(w.gridEnabled, isFalse);
    expect(w.tabs, isEmpty);
    expect(w.showingStartPage, isTrue);
    await db.close();
  });
}
