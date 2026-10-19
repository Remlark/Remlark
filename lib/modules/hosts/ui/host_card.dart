import 'package:flutter/material.dart';

import '../../../l10n/app_localizations.dart';
import '../host_model.dart';
import 'os_icon.dart';
import 'sync_badge.dart';

/// 主机卡片操作
enum HostAction { connect, edit, duplicate, toggleSync, delete }

/// 主机卡片：系统图标、名称、地址、协议、同步状态；双击或点击连接按钮打开会话
class HostCard extends StatefulWidget {
  const HostCard({super.key, required this.host, required this.groupName, required this.onAction});

  final HostEntry host;
  final String? groupName;
  final void Function(HostAction) onAction;

  @override
  State<HostCard> createState() => _HostCardState();
}

class _HostCardState extends State<HostCard> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final h = widget.host;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        onDoubleTap: () => widget.onAction(HostAction.connect),
        onSecondaryTapUp: (d) => _showMenu(d.globalPosition),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          decoration: BoxDecoration(
            color: theme.cardTheme.color,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: _hover ? scheme.primary.withValues(alpha: 0.6) : scheme.outlineVariant.withValues(alpha: 0.5),
            ),
            boxShadow: _hover
                ? [BoxShadow(color: scheme.primary.withValues(alpha: 0.08), blurRadius: 12, offset: const Offset(0, 4))]
                : null,
          ),
          padding: const EdgeInsets.fromLTRB(12, 10, 6, 10),
          child: Row(
            children: [
              OsIcon(host: h),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            h.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600),
                          ),
                        ),
                        const SizedBox(width: 6),
                        if (h.syncEnabled) SyncBadge(state: h.syncState),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      h.endpoint,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        _Chip(h.protocol.name.toUpperCase()),
                        if (h.jumpChain.isNotEmpty) ...[
                          const SizedBox(width: 4),
                          _Chip('${context.tr('host.jump')} ×${h.jumpChain.length}'),
                        ],
                        if (h.proxy.enabled) ...[const SizedBox(width: 4), _Chip(h.proxy.type.name.toUpperCase())],
                        if (h.osName != null) ...[
                          const SizedBox(width: 4),
                          Flexible(
                            child: Text(
                              h.osName!,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.labelSmall?.copyWith(color: scheme.outline),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
              AnimatedOpacity(
                opacity: _hover ? 1 : 0.0,
                duration: const Duration(milliseconds: 120),
                child: IconButton(
                  tooltip: context.tr('ssh.connect'),
                  icon: Icon(Icons.play_arrow_rounded, color: scheme.primary),
                  onPressed: () => widget.onAction(HostAction.connect),
                ),
              ),
              Builder(
                builder: (ctx) => IconButton(
                  icon: const Icon(Icons.more_vert, size: 18),
                  onPressed: () {
                    final box = ctx.findRenderObject() as RenderBox;
                    _showMenu(box.localToGlobal(box.size.bottomLeft(Offset.zero)));
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _showMenu(Offset pos) async {
    final h = widget.host;
    final r = await showMenu<HostAction>(
      context: context,
      position: RelativeRect.fromLTRB(pos.dx, pos.dy, pos.dx + 1, pos.dy + 1),
      items: [
        PopupMenuItem(value: HostAction.connect, child: _item(Icons.play_arrow_rounded, 'ssh.connect')),
        PopupMenuItem(value: HostAction.edit, child: _item(Icons.edit_outlined, 'common.edit')),
        PopupMenuItem(value: HostAction.duplicate, child: _item(Icons.copy_outlined, 'common.duplicate')),
        PopupMenuItem(
          value: HostAction.toggleSync,
          child: _item(
            h.syncEnabled ? Icons.cloud_off_outlined : Icons.cloud_upload_outlined,
            h.syncEnabled ? 'sync.remove' : 'sync.add',
          ),
        ),
        const PopupMenuDivider(),
        PopupMenuItem(value: HostAction.delete, child: _item(Icons.delete_outline, 'common.delete', danger: true)),
      ],
    );
    if (r != null) widget.onAction(r);
  }

  Widget _item(IconData icon, String key, {bool danger = false}) {
    final color = danger ? Colors.red : null;
    return Row(
      children: [
        Icon(icon, size: 18, color: color),
        const SizedBox(width: 10),
        Text(context.tr(key), style: TextStyle(color: color)),
      ],
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
      decoration: BoxDecoration(
        color: scheme.secondaryContainer.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        text,
        style: TextStyle(fontSize: 10, color: scheme.onSecondaryContainer, fontWeight: FontWeight.w600),
      ),
    );
  }
}
