import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../app/theme/app_palette.dart';
import '../../../app/theme/app_theme.dart';
import '../../../l10n/app_localizations.dart';
import '../../../ui_kit/app_dialog.dart';
import '../../../ui_kit/panel.dart';
import '../../hosts/host_model.dart';
import '../../hosts/vnc_ssh_config.dart';
import '../../hosts/hosts_controller.dart';
import '../../hosts/ui/os_icon.dart';
import '../../hosts/ui/protocol_tag.dart';
import '../../terminal/terminal_session.dart';

/// 选择结果：新连接的主机，或已打开的终端会话
class HostPick {
  const HostPick.host(HostEntry this.host) : session = null;
  const HostPick.session(TerminalSession this.session) : host = null;

  final HostEntry? host;
  final TerminalSession? session;
}

/// 主机选择弹窗：搜索主机并新建会话；广播添加时还列出已打开、尚未加入广播的终端
class HostPicker extends StatefulWidget {
  const HostPicker({
    super.key,
    required this.title,
    this.sshOnly = false,
    this.openSessions = const [],
  });

  final String title;

  /// 只列出 SSH 主机（广播只对终端有效）
  final bool sshOnly;

  /// 可直接加入的已打开会话
  final List<TerminalSession> openSessions;

  /// 显示选择器
  static Future<HostPick?> show(
    BuildContext context, {
    required String title,
    bool sshOnly = false,
    List<TerminalSession> openSessions = const [],
  }) {
    return showDialog<HostPick>(
      context: context,
      builder: (_) => HostPicker(
        title: title,
        sshOnly: sshOnly,
        openSessions: openSessions,
      ),
    );
  }

  @override
  State<HostPicker> createState() => _HostPickerState();
}

class _HostPickerState extends State<HostPicker> {
  String _q = '';

  bool _match(String name, String addr) {
    final q = _q.trim().toLowerCase();
    return q.isEmpty ||
        name.toLowerCase().contains(q) ||
        addr.toLowerCase().contains(q);
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final hosts = context
        .watch<HostsController>()
        .all
        .expand(
          (h) => h.connectionProtocols
              .where((p) => !widget.sshOnly || p == HostProtocol.ssh)
              .map(h.forConnection),
        )
        .where((h) => _match(h.name, h.address))
        .toList();
    final sessions = widget.openSessions
        .where((s) => _match(s.host.name, s.host.address))
        .toList();
    Widget section(String text) => Padding(
      padding: const EdgeInsets.fromLTRB(4, 14, 4, 6),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 12,
          color: p.textMuted,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
    return AppDialog(
      title: widget.title,
      width: 520,
      scrollable: false,
      content: SizedBox(
        height: 420,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SearchField(
              hint: context.tr('host.search'),
              onChanged: (v) => setState(() => _q = v),
            ),
            Expanded(
              child: ListView(
                children: [
                  if (sessions.isNotEmpty) ...[
                    section(context.tr('picker.open_sessions')),
                    for (final s in sessions)
                      _Row(
                        host: s.host,
                        subtitle: context.tr('picker.session_hint'),
                        onTap: () =>
                            Navigator.pop(context, HostPick.session(s)),
                      ),
                  ],
                  section(context.tr('picker.hosts')),
                  if (hosts.isEmpty)
                    Padding(
                      padding: const EdgeInsets.all(16),
                      child: Text(
                        context.tr('host.no_match'),
                        style: TextStyle(color: p.textFaint),
                      ),
                    ),
                  for (final h in hosts)
                    _Row(
                      host: h,
                      subtitle: h.endpoint,
                      onTap: () => Navigator.pop(context, HostPick.host(h)),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({required this.host, required this.subtitle, required this.onTap});

  final HostEntry host;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return InkWell(
      borderRadius: BorderRadius.circular(AppSizes.radius),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
        child: Row(
          children: [
            OsIcon(host: host, size: 30),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          host.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 14,
                            color: p.text,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      ProtocolTag.of(host.protocol, small: true),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 12, color: p.textMuted),
                  ),
                ],
              ),
            ),
            Icon(Icons.arrow_forward_rounded, size: 18, color: p.accent),
          ],
        ),
      ),
    );
  }
}
