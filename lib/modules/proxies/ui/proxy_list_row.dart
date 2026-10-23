import 'package:flutter/material.dart';

import '../../../app/theme/app_palette.dart';
import '../../../l10n/app_localizations.dart';
import '../../../ui_kit/app_menu.dart';
import '../proxy_profile.dart';

/// 管理弹窗的双行代理条目，以名称和地址为主，协议和使用数量为辅。
class ProxyListRow extends StatelessWidget {
  const ProxyListRow({
    super.key,
    required this.entry,
    required this.usage,
    required this.onEdit,
    required this.onDelete,
  });
  final ProxyEntry entry;
  final int usage;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  /// 整行可编辑；菜单保留编辑与删除，长名称和地址不会撑宽弹窗。
  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return InkWell(
      onTap: onEdit,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Row(
          children: [
            Icon(Icons.dns_outlined, size: 22, color: p.textMuted),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Tooltip(
                          message: entry.name,
                          child: Text(
                            entry.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w600,
                              color: p.text,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Text(
                        entry.protocolLabel,
                        style: TextStyle(fontSize: 12, color: p.textMuted),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Tooltip(
                    message: entry.endpoint,
                    child: Text(
                      entry.endpoint,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 13,
                        fontFamily: 'monospace',
                        color: p.textMuted,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 16),
            Text(
              context.tr(usage > 0 ? 'proxy.usage' : 'proxy.unused', {
                'count': usage,
              }),
              style: TextStyle(fontSize: 12, color: p.textMuted),
            ),
            const SizedBox(width: 8),
            AppMenuAnchor<String>(
              builder: (ctx, open) => IconButton(
                tooltip: ctx.tr('proxy.actions'),
                onPressed: open,
                icon: const Icon(Icons.more_horiz, size: 20),
              ),
              items: (ctx) => [
                AppMenuItem(
                  value: 'edit',
                  label: ctx.tr('common.edit'),
                  icon: Icons.edit_outlined,
                ),
                AppMenuItem(
                  value: 'delete',
                  label: ctx.tr('common.delete'),
                  icon: Icons.delete_outline,
                  danger: true,
                ),
              ],
              onSelected: (value) => value == 'edit' ? onEdit() : onDelete(),
            ),
          ],
        ),
      ),
    );
  }
}
