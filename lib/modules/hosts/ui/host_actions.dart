import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../app/theme/app_palette.dart';
import '../../../app/theme/app_theme.dart';
import '../../../l10n/app_localizations.dart';
import '../../../ui_kit/app_dialog.dart';
import '../../../ui_kit/buttons.dart';
import '../../../utils/ui_utils.dart';
import '../../sync/sync_service.dart';
import '../../workspace/session_launcher.dart';
import '../host_model.dart';
import '../hosts_controller.dart';
import 'host_card.dart';
import 'host_editor_dialog.dart';
import 'os_icon.dart';
import 'protocol_tag.dart';
import '../../../ui_kit/check_label.dart';

/// 主机操作执行：主机卡片、列表行、工作区最近连接共用
class HostActions {
  HostActions._();

  /// 执行主机操作
  static Future<void> run(
    BuildContext context,
    HostEntry h,
    HostAction a,
  ) async {
    final c = context.read<HostsController>();
    final sync = context.read<SyncService>();
    switch (a) {
      case HostAction.connect:
        await SessionLauncher.open(context, h);
      case HostAction.connectSsh:
        await SessionLauncher.open(context, h, protocol: HostProtocol.ssh);
      case HostAction.connectVnc:
        await SessionLauncher.open(context, h, protocol: HostProtocol.vnc);
      case HostAction.connectRdp:
        await SessionLauncher.open(context, h, protocol: HostProtocol.rdp);
      case HostAction.edit:
        await HostEditorDialog.show(context, existing: h);
      case HostAction.duplicate:
        await c.duplicate(h);
      case HostAction.toggleSync:
        try {
          if (h.syncEnabled) {
            final ok = await UiUtils.confirm(
              context,
              title: context.tr('sync.remove'),
              message: context.tr('sync.remove.message', {'name': h.name}),
              okText: context.tr('sync.remove'),
            );
            if (ok) await sync.removeFromServer(h.uuid);
          } else {
            await sync.enable(h);
            if (context.mounted && !sync.config.isConfigured) {
              UiUtils.toast(context.tr('sync.not_configured'));
            }
          }
        } catch (e) {
          UiUtils.toast('$e', error: true);
        }
      case HostAction.delete:
        await _delete(context, h, c, sync);
    }
  }

  /// 删除确认：显示主机摘要；已参与同步且配置了服务器时可同时从服务器删除
  static Future<void> _delete(
    BuildContext context,
    HostEntry h,
    HostsController c,
    SyncService sync,
  ) async {
    var alsoRemote = true;
    final synced = h.syncEnabled && sync.config.isConfigured;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setState) {
          final p = ctx.palette;
          return AppDialog(
            title: ctx.tr('host.delete'),
            icon: Icons.delete_outline_rounded,
            iconColor: p.danger,
            content: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: p.input,
                    borderRadius: BorderRadius.circular(AppSizes.radius),
                    border: Border.all(color: p.border),
                  ),
                  child: Row(
                    children: [
                      OsIcon(host: h, size: 34),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Flexible(
                                  child: Text(
                                    h.name,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      fontWeight: FontWeight.w600,
                                      color: p.text,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                ProtocolTag.of(h.protocol, small: true),
                              ],
                            ),
                            const SizedBox(height: 3),
                            Text(
                              '${h.username.isEmpty ? '' : '${h.username}@'}${h.address}:${h.port}',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 13,
                                color: p.textMuted,
                                fontFamily: 'monospace',
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 14),
                Text(ctx.tr('host.delete.message', {'name': h.name})),
                if (synced)
                  CheckLabel(
                    value: alsoRemote,
                    onChanged: (v) => setState(() => alsoRemote = v),
                    label: ctx.tr('host.delete.remote'),
                  ),
              ],
            ),
            actions: [
              OutlinedButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: Text(ctx.tr('common.cancel')),
              ),
              DangerButton(
                label: ctx.tr('host.delete'),
                onPressed: () => Navigator.pop(ctx, true),
              ),
            ],
          );
        },
      ),
    );
    if (ok != true) return;
    if (synced && alsoRemote) {
      try {
        await sync.removeFromServer(h.uuid);
      } catch (e) {
        UiUtils.toast('$e', error: true);
      }
    }
    await c.deleteHost(h.uuid);
  }
}
