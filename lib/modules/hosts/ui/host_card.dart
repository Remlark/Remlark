import 'package:flutter/material.dart';

import '../../../app/theme/app_palette.dart';
import '../../../app/theme/app_theme.dart';
import '../../../l10n/app_localizations.dart';
import '../../../ui_kit/buttons.dart';
import '../../../utils/format_utils.dart';
import '../host_model.dart';
import '../vnc_ssh_config.dart';
import 'os_icon.dart';
import 'protocol_tag.dart';
import 'sync_badge.dart';
import '../../../ui_kit/app_menu.dart';

/// 主机卡片操作
enum HostAction {
  connect,
  connectSsh,
  connectVnc,
  connectRdp,
  edit,
  duplicate,
  toggleSync,
  delete,
}

/// 主机卡片：系统图标、名称、协议、地址 / 用户名 / 上次连接、同步状态与连接按钮。
/// 单协议卡片可双击连接，右下角协议图标打开对应会话，右键或“更多”打开操作菜单
class HostCard extends StatefulWidget {
  const HostCard({
    super.key,
    required this.host,
    required this.onAction,
    this.showSync = true,
  });

  final HostEntry host;
  final void Function(HostAction) onAction;

  /// 底部显示同步状态（最近连接卡片显示“已连接过”）
  final bool showSync;

  @override
  State<HostCard> createState() => _HostCardState();
}

class _HostCardState extends State<HostCard> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final h = widget.host;
    final p = context.palette;
    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        onDoubleTap: h.connectionProtocols.length == 1
            ? () => widget.onAction(HostAction.connect)
            : null,
        onSecondaryTapUp: (d) =>
            showHostMenu(context, h, d.globalPosition, widget.onAction),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          decoration: BoxDecoration(
            color: _hover
                ? Color.alphaBlend(p.hover.withValues(alpha: 0.5), p.panel)
                : p.panel,
            borderRadius: BorderRadius.circular(AppSizes.radiusLarge),
            border: Border.all(
              color: _hover ? p.accent.withValues(alpha: 0.5) : p.border,
            ),
          ),
          padding: const EdgeInsets.fromLTRB(18, 14, 12, 14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  OsIcon(host: h, size: 38),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Row(
                      children: [
                        Flexible(
                          child: Text(
                            h.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                              color: p.text,
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        HostProtocolTags(host: h),
                      ],
                    ),
                  ),
                  Builder(
                    builder: (ctx) => GhostIconButton(
                      icon: Icons.more_horiz,
                      tooltip: context.tr('common.more'),
                      onPressed: () {
                        final box = ctx.findRenderObject() as RenderBox;
                        showHostMenu(
                          context,
                          h,
                          box.localToGlobal(box.size.bottomLeft(Offset.zero)),
                          widget.onAction,
                        );
                      },
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              _kv(
                context,
                context.tr('host.address'),
                h.port == h.protocol.defaultPort
                    ? h.address
                    : '${h.address}:${h.port}',
              ),
              _kv(
                context,
                context.tr('host.username'),
                h.username.isEmpty ? '—' : h.username,
              ),
              _kv(
                context,
                context.tr('host.last_connected'),
                h.lastConnectedAt == null
                    ? context.tr('host.never_connected')
                    : FormatUtils.dateTime(
                        DateTime.fromMillisecondsSinceEpoch(h.lastConnectedAt!),
                      ),
              ),
              const Spacer(),
              Row(
                children: [
                  Expanded(
                    child: widget.showSync
                        ? SyncBadge(state: h.syncState, withText: true)
                        : _connectedBefore(context),
                  ),
                  HostConnectButtons(host: h, onAction: widget.onAction),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _connectedBefore(BuildContext context) {
    final p = context.palette;
    return Row(
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(color: p.success, shape: BoxShape.circle),
        ),
        const SizedBox(width: 8),
        Flexible(
          child: Text(
            context.tr('workspace.connected_before'),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 13, color: p.success),
          ),
        ),
      ],
    );
  }

  /// 键值行：左侧标签，右侧等宽字体值
  Widget _kv(BuildContext context, String k, String v) {
    final p = context.palette;
    return Padding(
      padding: const EdgeInsets.only(bottom: 7),
      child: Row(
        children: [
          SizedBox(
            width: 84,
            child: Text(
              k,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 13, color: p.textMuted),
            ),
          ),
          Expanded(
            child: Text(
              v,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 13,
                color: p.text,
                fontFamily: 'monospace',
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// 按实际协议显示统一的连接入口，卡片、最近连接与列表共用。
class HostConnectButtons extends StatelessWidget {
  const HostConnectButtons({
    super.key,
    required this.host,
    required this.onAction,
    this.compact = false,
  });

  final HostEntry host;
  final void Function(HostAction) onAction;
  final bool compact;

  /// 根据可用协议显示连接按钮；双协议主机必须明确选择连接方式。
  @override
  Widget build(BuildContext context) {
    final protocols = host.connectionProtocols;
    return Row(
      mainAxisSize: MainAxisSize.min,
      spacing: 8,
      children: [
        for (final protocol in protocols)
          _ConnectButton(
            icon: switch (protocol) {
              HostProtocol.ssh => Icons.terminal_rounded,
              HostProtocol.vnc => Icons.desktop_windows_outlined,
              HostProtocol.rdp => Icons.window_rounded,
            },
            tooltip: context.tr('host.connect.${protocol.name}'),
            compact: compact,
            onPressed: () => onAction(
              protocols.length == 1
                  ? HostAction.connect
                  : switch (protocol) {
                      HostProtocol.ssh => HostAction.connectSsh,
                      HostProtocol.vnc => HostAction.connectVnc,
                      HostProtocol.rdp => HostAction.connectRdp,
                    },
            ),
          ),
      ],
    );
  }
}

/// 统一圆形连接按钮：终端与桌面共用强调色和交互状态。
class _ConnectButton extends StatelessWidget {
  const _ConnectButton({
    required this.onPressed,
    required this.icon,
    required this.tooltip,
    this.compact = false,
  });

  final VoidCallback onPressed;
  final IconData icon;
  final String tooltip;
  final bool compact;

  /// 复用卡片连接按钮的尺寸、圆形轮廓和悬停反馈，并提供可访问名称。
  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final label = tooltip;
    final size = compact ? 32.0 : 40.0;
    return Semantics(
      button: true,
      label: label,
      child: Tooltip(
        message: label,
        excludeFromSemantics: true,
        child: Material(
          color: p.accentFill,
          shape: const CircleBorder(),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            customBorder: const CircleBorder(),
            onTap: onPressed,
            mouseCursor: SystemMouseCursors.click,
            // 使用图标前景色叠加，保证明暗主题的实心底色都有可见反馈。
            overlayColor: WidgetStateProperty.resolveWith((states) {
              if (states.contains(WidgetState.pressed))
                return p.onAccent.withValues(alpha: 0.20);
              if (states.contains(WidgetState.hovered) ||
                  states.contains(WidgetState.focused)) {
                return p.onAccent.withValues(alpha: 0.12);
              }
              return Colors.transparent;
            }),
            child: SizedBox(
              width: size,
              height: size,
              child: Icon(icon, size: compact ? 17 : 20, color: p.onAccent),
            ),
          ),
        ),
      ),
    );
  }
}

/// 主机操作菜单（卡片、列表行、最近连接共用）
Future<void> showHostMenu(
  BuildContext context,
  HostEntry h,
  Offset pos,
  void Function(HostAction) onAction,
) async {
  AppMenuItem<HostAction> item(
    HostAction value,
    IconData icon,
    String key, {
    bool danger = false,
  }) => AppMenuItem(
    value: value,
    icon: icon,
    label: context.tr(key),
    danger: danger,
  );

  final r = await AppMenu.showAt<HostAction>(context, pos, [
    if (h.connectionProtocols.length > 1) ...[
      for (final protocol in h.connectionProtocols)
        item(
          switch (protocol) {
            HostProtocol.ssh => HostAction.connectSsh,
            HostProtocol.vnc => HostAction.connectVnc,
            HostProtocol.rdp => HostAction.connectRdp,
          },
          switch (protocol) {
            HostProtocol.ssh => Icons.terminal_rounded,
            HostProtocol.vnc => Icons.desktop_windows_outlined,
            HostProtocol.rdp => Icons.window_rounded,
          },
          'host.connect.${protocol.name}',
        ),
    ] else
      item(HostAction.connect, switch (h.protocol) {
        HostProtocol.ssh => Icons.terminal_rounded,
        HostProtocol.vnc => Icons.desktop_windows_outlined,
        HostProtocol.rdp => Icons.window_rounded,
      }, 'host.connect.${h.protocol.name}'),
    item(HostAction.edit, Icons.edit_outlined, 'common.edit'),
    item(HostAction.duplicate, Icons.copy_outlined, 'common.duplicate'),
    item(
      HostAction.toggleSync,
      h.syncEnabled ? Icons.cloud_off_outlined : Icons.cloud_upload_outlined,
      h.syncEnabled ? 'sync.remove' : 'sync.add',
    ),
    const AppMenuDivider(),
    item(
      HostAction.delete,
      Icons.delete_outline,
      'common.delete',
      danger: true,
    ),
  ]);
  if (r != null) onAction(r);
}
