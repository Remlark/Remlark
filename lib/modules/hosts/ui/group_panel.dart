import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../app/theme/app_palette.dart';
import '../../../l10n/app_localizations.dart';
import '../../../ui_kit/buttons.dart';
import '../../../ui_kit/nav_tile.dart';
import '../../../utils/id_utils.dart';
import '../../../utils/ui_utils.dart';
import '../host_model.dart';
import '../hosts_controller.dart';

/// 主机分组二级导航：全部主机 / 各分组 / 未分组，支持新建；分组右键重命名、删除
class GroupPanel extends StatelessWidget {
  const GroupPanel({super.key});

  @override
  Widget build(BuildContext context) {
    final c = context.watch<HostsController>();
    final ungrouped = c.countInGroup(HostsController.ungrouped);
    return SubNav(
      title: context.tr('group.title'),
      titleAction: GhostIconButton(
        icon: Icons.add,
        tooltip: context.tr('group.new'),
        onPressed: () => _newGroup(context, c),
      ),
      children: [
        _tile(context, c, null, Icons.desktop_windows_outlined, context.tr('group.all')),
        for (final g in c.groups) _tile(context, c, g, Icons.layers_outlined, g.name),
        if (ungrouped > 0 && c.groups.isNotEmpty)
          _tile(context, c, null, Icons.folder_outlined, context.tr('group.none'), id: HostsController.ungrouped),
      ],
    );
  }

  Widget _tile(BuildContext context, HostsController c, GroupEntry? g, IconData icon, String name, {String? id}) {
    final key = id ?? g?.uuid;
    return NavTile(
      icon: icon,
      label: name,
      selected: c.selectedGroup == key,
      trailing: Text('${c.countInGroup(key)}'),
      onTap: () => c.setGroup(key),
      onSecondaryTapUp: g == null ? null : (d) => _menu(context, d.globalPosition, g, c),
    );
  }

  Future<void> _newGroup(BuildContext context, HostsController c) async {
    final name = await UiUtils.prompt(context, title: context.tr('group.new'), label: context.tr('group.name'));
    if (name == null || name.trim().isEmpty) return;
    await c.saveGroup(GroupEntry(uuid: IdUtils.newId(), name: name.trim(), sortOrder: c.groups.length));
  }

  Future<void> _menu(BuildContext context, Offset pos, GroupEntry g, HostsController c) async {
    final p = context.palette;
    final r = await showMenu<String>(
      context: context,
      position: RelativeRect.fromLTRB(pos.dx, pos.dy, pos.dx + 1, pos.dy + 1),
      items: [
        PopupMenuItem(value: 'rename', child: Text(context.tr('common.rename'))),
        PopupMenuItem(
          value: 'delete',
          child: Text(context.tr('common.delete'), style: TextStyle(color: p.danger)),
        ),
      ],
    );
    if (!context.mounted) return;
    if (r == 'rename') {
      final name = await UiUtils.prompt(
        context,
        title: context.tr('group.rename'),
        label: context.tr('group.name'),
        initial: g.name,
      );
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
