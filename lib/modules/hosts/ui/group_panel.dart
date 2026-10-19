import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../l10n/app_localizations.dart';
import '../../../utils/id_utils.dart';
import '../../../utils/ui_utils.dart';
import '../host_model.dart';
import '../hosts_controller.dart';

/// 分组侧栏：全部 / 各分组，支持新建、重命名、删除
class GroupPanel extends StatelessWidget {
  const GroupPanel({super.key});

  @override
  Widget build(BuildContext context) {
    final c = context.watch<HostsController>();
    final scheme = Theme.of(context).colorScheme;
    return SizedBox(
      width: 200,
      child: Material(
        color: scheme.surfaceContainerLow,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 8, 8),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      context.tr('group.title'),
                      style: Theme.of(context).textTheme.labelLarge?.copyWith(color: scheme.onSurfaceVariant),
                    ),
                  ),
                  IconButton(
                    tooltip: context.tr('group.new'),
                    icon: const Icon(Icons.create_new_folder_outlined, size: 18),
                    onPressed: () => _newGroup(context, c),
                  ),
                ],
              ),
            ),
            _tile(context, null, Icons.all_inbox_outlined, context.tr('group.all'), c.countInGroup(null), c),
            Expanded(
              child: ListView(
                children: [
                  for (final g in c.groups) _tile(context, g, Icons.folder_outlined, g.name, c.countInGroup(g.uuid), c),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _tile(BuildContext context, GroupEntry? g, IconData icon, String name, int count, HostsController c) {
    final selected = c.selectedGroup == g?.uuid;
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 1),
      child: GestureDetector(
        onSecondaryTapUp: g == null ? null : (d) => _menu(context, d.globalPosition, g, c),
        child: ListTile(
          dense: true,
          selected: selected,
          selectedTileColor: scheme.primaryContainer.withValues(alpha: 0.6),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          leading: Icon(icon, size: 18),
          title: Text(name, maxLines: 1, overflow: TextOverflow.ellipsis),
          trailing: Text('$count', style: Theme.of(context).textTheme.labelSmall),
          onTap: () => c.setGroup(g?.uuid),
        ),
      ),
    );
  }

  Future<void> _newGroup(BuildContext context, HostsController c) async {
    final name = await UiUtils.prompt(context, title: context.tr('group.new'), label: context.tr('group.name'));
    if (name == null || name.trim().isEmpty) return;
    await c.saveGroup(GroupEntry(uuid: IdUtils.newId(), name: name.trim(), sortOrder: c.groups.length));
  }

  Future<void> _menu(BuildContext context, Offset pos, GroupEntry g, HostsController c) async {
    final r = await showMenu<String>(
      context: context,
      position: RelativeRect.fromLTRB(pos.dx, pos.dy, pos.dx + 1, pos.dy + 1),
      items: [
        PopupMenuItem(value: 'rename', child: Text(context.tr('common.rename'))),
        PopupMenuItem(
          value: 'delete',
          child: Text(context.tr('common.delete'), style: const TextStyle(color: Colors.red)),
        ),
      ],
    );
    if (!context.mounted) return;
    if (r == 'rename') {
      final name = await UiUtils.prompt(context, title: context.tr('common.rename'), initial: g.name);
      if (name != null && name.trim().isNotEmpty) {
        await c.saveGroup(GroupEntry(uuid: g.uuid, name: name.trim(), sortOrder: g.sortOrder));
      }
    } else if (r == 'delete') {
      final ok = await UiUtils.confirm(
        context,
        title: context.tr('group.delete'),
        message: context.tr('group.delete.message', {'name': g.name}),
        danger: true,
      );
      if (ok) await c.deleteGroup(g.uuid);
    }
  }
}
