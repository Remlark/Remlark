import 'dart:async';

import 'package:flutter/material.dart';

import '../../../app/theme/app_palette.dart';
import '../../../l10n/app_localizations.dart';
import '../../../utils/format_utils.dart';
import '../../hosts/ui/os_icon.dart';
import '../workspace_tab.dart';

/// 会话底部状态栏（终端、RDP、VNC 共用）：主机、地址、连接状态与时长、用户、协议，右侧可附加信息
class SessionStatusBar extends StatefulWidget {
  const SessionStatusBar({
    super.key,
    required this.tab,
    this.detail,
    this.trailing = const [],
  });

  final WorkspaceTab tab;

  /// 协议附加说明（如分辨率、系统名称）
  final String? detail;

  /// 右侧附加组件
  final List<Widget> trailing;

  @override
  State<SessionStatusBar> createState() => _SessionStatusBarState();
}

class _SessionStatusBarState extends State<SessionStatusBar> {
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    // 每秒刷新连接时长
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted && widget.tab.connectedAt != null) setState(() {});
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final t = widget.tab;
    final h = t.host;
    final (color, key) = switch (t.state) {
      SessionState.connecting => (p.warning, 'session.state.connecting'),
      SessionState.connected => (p.success, 'session.state.connected'),
      SessionState.disconnected => (p.textFaint, 'session.state.disconnected'),
      SessionState.failed => (p.danger, 'session.state.failed'),
    };
    final style = TextStyle(fontSize: 12.5, color: p.textMuted);
    final since = t.connectedAt;
    Widget sep() => Container(
      width: 1,
      height: 14,
      margin: const EdgeInsets.symmetric(horizontal: 12),
      color: p.border,
    );
    return Container(
      height: 30,
      padding: const EdgeInsets.symmetric(horizontal: 14),
      decoration: BoxDecoration(
        color: p.sidebar,
        border: Border(top: BorderSide(color: p.border)),
      ),
      child: Row(
        children: [
          OsIcon(host: h, size: 16),
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              h.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 12.5, color: p.text),
            ),
          ),
          const SizedBox(width: 12),
          Text(
            '${h.address}:${h.port}',
            style: style.copyWith(fontFamily: 'monospace'),
          ),
          sep(),
          Container(
            width: 7,
            height: 7,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 6),
          Text(context.tr(key), style: style.copyWith(color: color)),
          if (since != null) ...[
            const SizedBox(width: 10),
            Text(
              FormatUtils.duration(DateTime.now().difference(since)),
              style: style.copyWith(fontFamily: 'monospace'),
            ),
          ],
          if (h.username.isNotEmpty) ...[sep(), Text(h.username, style: style)],
          sep(),
          Expanded(
            child: Text(
              [t.kindLabel, ?widget.detail].join(' · '),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: style,
            ),
          ),
          ...widget.trailing,
        ],
      ),
    );
  }
}
