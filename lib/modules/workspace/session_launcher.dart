import 'package:flutter/widgets.dart';
import 'package:provider/provider.dart';

import '../../app/app_services.dart';
import '../../app/nav_controller.dart';
import '../hosts/host_model.dart';
import '../hosts/vnc_ssh_config.dart';
import '../remote_desktop/rdp/rdp_session.dart';
import '../remote_desktop/vnc/vnc_session.dart';
import '../ssh/ui/ssh_dialogs.dart';
import '../terminal/terminal_session.dart';
import 'workspace_tab.dart';

/// 会话启动器：根据主机协议创建对应的标签页并开始连接，然后切到工作区
class SessionLauncher {
  SessionLauncher._();

  static final DialogInteraction _ui = DialogInteraction();

  /// 打开主机。[broadcast] 为 true 时新终端加入广播分组（来自广播条“添加”）
  static Future<void> open(
    BuildContext context,
    HostEntry host, {
    bool broadcast = false,
    HostProtocol? protocol,
  }) async {
    final services = context.read<AppServices>();
    final nav = context.read<NavController>();
    final workspace = services.workspace;
    // 从数据库取最新数据（包含保存的密码）
    final saved = await services.hostRepo.getByUuid(host.uuid) ?? host;
    final fresh = saved.forConnection(protocol ?? host.protocol);
    final WorkspaceTab tab = switch (fresh.protocol) {
      HostProtocol.ssh => TerminalSession(fresh, services.connector, _ui),
      HostProtocol.vnc => VncSession(
        fresh,
        services.hostRepo,
        services.connector,
        _ui,
        _ui,
      ),
      HostProtocol.rdp => RdpSession(fresh, services.hostRepo, _ui),
    };
    workspace.add(tab);
    // 新会话默认独立输入，只有显式从广播目标入口添加才加入。
    if (broadcast && workspace.broadcast && tab is TerminalSession) {
      workspace.addToBroadcast(tab.id);
    }
    nav.go(AppPage.sessions);
    switch (tab) {
      case TerminalSession t:
        await t.connect();
      case VncSession t:
        await t.connect();
      case RdpSession t:
        await t.connect();
    }
    if (tab.state == SessionState.connected) {
      // 连接成功后刷新主机列表（最近连接、探测到的系统信息）
      Future.delayed(const Duration(seconds: 3), services.hosts.load);
    }
  }
}
