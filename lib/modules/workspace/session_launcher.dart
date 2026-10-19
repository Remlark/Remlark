import 'package:flutter/widgets.dart';
import 'package:provider/provider.dart';

import '../../app/app_services.dart';
import '../../app/nav_controller.dart';
import '../hosts/host_model.dart';
import '../remote_desktop/rdp/rdp_session.dart';
import '../remote_desktop/vnc/vnc_session.dart';
import '../ssh/ui/ssh_dialogs.dart';
import '../terminal/terminal_session.dart';
import 'workspace_tab.dart';

/// 会话启动器：根据主机协议创建对应的标签页并开始连接，然后切到会话页
class SessionLauncher {
  SessionLauncher._();

  static final DialogInteraction _ui = DialogInteraction();

  /// 打开主机
  static Future<void> open(BuildContext context, HostEntry host) async {
    final services = context.read<AppServices>();
    final nav = context.read<NavController>();
    // 从数据库取最新数据（包含保存的密码）
    final fresh = await services.hostRepo.getByUuid(host.uuid) ?? host;
    final WorkspaceTab tab;
    switch (fresh.protocol) {
      case HostProtocol.ssh:
        final t = TerminalSession(fresh, services.connector, _ui);
        tab = t;
        services.workspace.add(t);
        nav.go(AppPage.sessions);
        await t.connect();
      case HostProtocol.vnc:
        final t = VncSession(fresh, services.hostRepo, services.connector, _ui, _ui);
        tab = t;
        services.workspace.add(t);
        nav.go(AppPage.sessions);
        await t.connect();
      case HostProtocol.rdp:
        final t = RdpSession(fresh, services.hostRepo, _ui);
        tab = t;
        services.workspace.add(t);
        nav.go(AppPage.sessions);
        await t.connect();
    }
    if (tab.state == SessionState.connected) {
      // 连接成功后刷新主机列表（最近连接、探测到的系统信息）
      Future.delayed(const Duration(seconds: 3), services.hosts.load);
    }
  }
}
