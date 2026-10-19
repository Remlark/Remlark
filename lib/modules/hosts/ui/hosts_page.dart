import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../l10n/app_localizations.dart';
import '../../../utils/format_utils.dart';
import '../../../utils/ui_utils.dart';
import '../../sync/sync_service.dart';
import '../../workspace/session_launcher.dart';
import '../host_model.dart';
import '../hosts_controller.dart';
import 'group_panel.dart';
import 'host_card.dart';
import 'host_editor_dialog.dart';

/// 主机页：分组侧栏 + 顶部工具栏（搜索、协议筛选、同步、新建）+ 主机卡片网格
class HostsPage extends StatelessWidget {
  const HostsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        const GroupPanel(),
        const VerticalDivider(width: 1),
        Expanded(
          child: Column(
            children: [
              const _Toolbar(),
              const Divider(height: 1),
              Expanded(child: _HostGrid()),
            ],
          ),
        ),
      ],
    );
  }
}

class _Toolbar extends StatelessWidget {
  const _Toolbar();

  @override
  Widget build(BuildContext context) {
    final c = context.watch<HostsController>();
    final sync = context.watch<SyncService>();
    final search = TextField(
      decoration: InputDecoration(prefixIcon: const Icon(Icons.search, size: 18), hintText: context.tr('host.search')),
      onChanged: c.setSearch,
    );
    final filter = SegmentedButton<ProtocolFilter>(
      showSelectedIcon: false,
      segments: [
        ButtonSegment(value: ProtocolFilter.all, label: Text(context.tr('common.all'))),
        const ButtonSegment(value: ProtocolFilter.ssh, label: Text('SSH')),
        const ButtonSegment(value: ProtocolFilter.rdp, label: Text('RDP')),
        const ButtonSegment(value: ProtocolFilter.vnc, label: Text('VNC')),
      ],
      selected: {c.protocolFilter},
      onSelectionChanged: (s) => c.setProtocolFilter(s.first),
    );
    final actions = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (sync.config.isConfigured) _SyncButton(sync: sync),
        const SizedBox(width: 8),
        _NewHostButton(groupUuid: c.selectedGroup),
      ],
    );
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 14),
      // 宽度不足时协议筛选换到第二行，搜索框随宽度伸缩，避免溢出
      child: LayoutBuilder(
        builder: (context, box) {
          if (box.maxWidth >= 760) {
            return Row(
              children: [
                Flexible(
                  child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 320), child: search),
                ),
                const SizedBox(width: 12),
                filter,
                const Spacer(),
                actions,
              ],
            );
          }
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(child: search),
                  const SizedBox(width: 8),
                  actions,
                ],
              ),
              const SizedBox(height: 10),
              filter,
            ],
          );
        },
      ),
    );
  }
}

/// 立即同步按钮（显示上次同步时间或错误）
class _SyncButton extends StatelessWidget {
  const _SyncButton({required this.sync});

  final SyncService sync;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: sync.lastError != null
          ? context.tr(sync.lastError!)
          : sync.config.lastSyncAt == null
          ? context.tr('sync.never')
          : context.tr('sync.last', {
              'time': FormatUtils.dateTime(DateTime.fromMillisecondsSinceEpoch(sync.config.lastSyncAt!)),
            }),
      child: IconButton(
        onPressed: sync.syncing
            ? null
            : () async {
                try {
                  final r = await sync.syncNow();
                  if (context.mounted) {
                    UiUtils.toast(context.tr('sync.done', {'pushed': r.pushed, 'pulled': r.pulled}));
                  }
                } catch (e) {
                  if (context.mounted) UiUtils.toast(context.tr(sync.lastError ?? '$e'), error: true);
                }
              },
        icon: sync.syncing
            ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
            : Icon(Icons.sync, color: sync.lastError != null ? Colors.red : null),
      ),
    );
  }
}

/// 新建主机按钮（选择协议）
class _NewHostButton extends StatelessWidget {
  const _NewHostButton({this.groupUuid});

  final String? groupUuid;

  @override
  Widget build(BuildContext context) {
    return MenuAnchor(
      builder: (ctx, ctrl, _) => FilledButton.icon(
        onPressed: () => ctrl.isOpen ? ctrl.close() : ctrl.open(),
        icon: const Icon(Icons.add, size: 18),
        label: Text(context.tr('host.new')),
      ),
      menuChildren: [
        for (final p in HostProtocol.values)
          MenuItemButton(
            leadingIcon: Icon(switch (p) {
              HostProtocol.ssh => Icons.terminal,
              HostProtocol.rdp => Icons.window,
              HostProtocol.vnc => Icons.desktop_windows_outlined,
            }, size: 18),
            onPressed: () => HostEditorDialog.show(context, protocol: p, groupUuid: groupUuid),
            child: Text(p.name.toUpperCase()),
          ),
      ],
    );
  }
}

class _HostGrid extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final c = context.watch<HostsController>();
    final hosts = c.visible;
    if (c.loading) return const Center(child: CircularProgressIndicator());
    if (hosts.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.dns_outlined, size: 56, color: Theme.of(context).colorScheme.outline),
            const SizedBox(height: 12),
            Text(context.tr(c.all.isEmpty ? 'host.empty' : 'host.no_match')),
            if (c.all.isEmpty) ...[
              const SizedBox(height: 16),
              FilledButton.tonal(
                onPressed: () => HostEditorDialog.show(context, protocol: HostProtocol.ssh),
                child: Text(context.tr('host.new')),
              ),
            ],
          ],
        ),
      );
    }
    final groupNames = {for (final g in c.groups) g.uuid: g.name};
    return LayoutBuilder(
      builder: (context, box) {
        final cols = (box.maxWidth / 340).floor().clamp(1, 6);
        return GridView.builder(
          padding: const EdgeInsets.all(20),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: cols,
            mainAxisExtent: 84,
            crossAxisSpacing: 12,
            mainAxisSpacing: 12,
          ),
          itemCount: hosts.length,
          itemBuilder: (context, i) {
            final h = hosts[i];
            return HostCard(
              key: ValueKey(h.uuid),
              host: h,
              groupName: groupNames[h.groupUuid],
              onAction: (a) => _onAction(context, h, a),
            );
          },
        );
      },
    );
  }

  Future<void> _onAction(BuildContext context, HostEntry h, HostAction a) async {
    final c = context.read<HostsController>();
    final sync = context.read<SyncService>();
    switch (a) {
      case HostAction.connect:
        await SessionLauncher.open(context, h);
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
            );
            if (ok) await sync.removeFromServer(h.uuid);
          } else {
            await sync.enable(h);
            if (context.mounted && !sync.config.isConfigured) UiUtils.toast(context.tr('sync.not_configured'));
          }
        } catch (e) {
          UiUtils.toast('$e', error: true);
        }
      case HostAction.delete:
        await _delete(context, h, c, sync);
    }
  }

  Future<void> _delete(BuildContext context, HostEntry h, HostsController c, SyncService sync) async {
    var alsoRemote = true;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setState) => AlertDialog(
          title: Text(ctx.tr('host.delete')),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(ctx.tr('host.delete.message', {'name': h.name})),
              if (h.syncEnabled && sync.config.isConfigured)
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  controlAffinity: ListTileControlAffinity.leading,
                  value: alsoRemote,
                  onChanged: (v) => setState(() => alsoRemote = v ?? true),
                  title: Text(ctx.tr('host.delete.remote')),
                ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(ctx.tr('common.cancel'))),
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: Colors.red.shade600),
              onPressed: () => Navigator.pop(ctx, true),
              child: Text(ctx.tr('common.delete')),
            ),
          ],
        ),
      ),
    );
    if (ok != true) return;
    if (h.syncEnabled && sync.config.isConfigured && alsoRemote) {
      try {
        await sync.removeFromServer(h.uuid);
      } catch (e) {
        UiUtils.toast('$e', error: true);
      }
    }
    await c.deleteHost(h.uuid);
  }
}
