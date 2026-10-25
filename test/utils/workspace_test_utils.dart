import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:remlark/app/app_services.dart';
import 'package:remlark/data/database.dart';
import 'package:remlark/modules/remote_desktop/rdp/rdp_session.dart';
import 'package:remlark/modules/remote_desktop/vnc/vnc_session.dart';
import 'package:remlark/modules/workspace/workspace_tab.dart';
import 'package:remlark/modules/hosts/host_model.dart';
import 'package:remlark/modules/ssh/ssh_connector.dart';
import 'package:remlark/modules/ssh/ui/ssh_dialogs.dart';
import 'package:remlark/modules/terminal/terminal_session.dart';

/// 记录广播输入，不发起网络连接。
class RecordingTerminal extends TerminalSession {
  RecordingTerminal(HostEntry host, SshConnector connector)
    : super(host, connector, DialogInteraction());
  final received = <String>[];

  /// 收集输入以验证广播目标，不向网络发送数据。
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

/// 每个场景独立创建真实会话模型，但不连接远端或加载原生客户端。
AppServices fixture() {
  final services = AppServices(AppDatabase(NativeDatabase.memory()));
  addTearDown(() async {
    await services.workspace.closeAll();
    services.workspace.dispose();
    await services.db.close();
  });
  return services;
}

/// 打开指定协议的会话，验证三个协议共用的布局路径。
WorkspaceTab open(AppServices s, HostProtocol protocol, String name) {
  final h = host(name, protocol);
  final ui = DialogInteraction();
  final tab = switch (protocol) {
    HostProtocol.ssh => RecordingTerminal(h, s.connector),
    HostProtocol.vnc => VncSession(h, s.hostRepo, s.connector, ui, ui),
    HostProtocol.rdp => RdpSession(h, s.hostRepo, ui),
  };
  s.workspace.add(tab);
  return tab;
}
