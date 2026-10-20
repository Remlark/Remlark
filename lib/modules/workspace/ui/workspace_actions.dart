import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../app/theme/app_palette.dart';
import '../../../l10n/app_localizations.dart';
import '../../../ui_kit/buttons.dart';
import '../workspace_controller.dart';
import 'session_selection_dialog.dart';

/// 标题栏最右侧的独立操作区：SSH 广播与布局，始终只有一行。
class WorkspaceActions extends StatelessWidget {
  const WorkspaceActions({super.key});

  /// 广播与布局分别显示，广播中锁定布局入口。
  @override
  Widget build(BuildContext context) {
    final w = context.watch<WorkspaceController>();
    final p = context.palette;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (w.terminals.isNotEmpty) ...[
          ToolButton(
            compact: true,
            icon: Icons.podcasts_rounded,
            label: w.broadcast
                ? context.tr('workspace.broadcast.count', {
                    'n': w.broadcastIds.length,
                  })
                : context.tr('workspace.broadcast'),
            selected: w.broadcast,
            color: w.broadcast ? p.warning : null,
            tooltip: context.tr('workspace.broadcast.choose_hint'),
            onPressed: () =>
                SessionSelectionDialog.show(context, w, broadcast: true),
          ),
          if (w.broadcast) ...[
            const SizedBox(width: 6),
            ToolButton(
              compact: true,
              icon: Icons.stop_rounded,
              color: p.danger,
              tooltip: context.tr('workspace.broadcast.stop'),
              onPressed: w.stopBroadcast,
            ),
          ],
          Container(
            width: 1,
            height: 20,
            color: p.border,
            margin: const EdgeInsets.symmetric(horizontal: 12),
          ),
        ],
        if (w.gridEnabled && w.focusedGridId != null)
          ToolButton(
            compact: true,
            icon: Icons.grid_view_rounded,
            label: context.tr('workspace.grid.return'),
            tooltip: context.tr(
              w.broadcast ? 'workspace.layout.locked' : 'workspace.grid.return',
            ),
            onPressed: w.broadcast ? null : w.returnToGrid,
          )
        else
          MenuAnchor(
            style: MenuStyle(
              elevation: const WidgetStatePropertyAll(0),
              side: WidgetStatePropertyAll(BorderSide(color: p.borderStrong)),
            ),
            builder: (ctx, menu, _) => ToolButton(
              key: const ValueKey('workspace-layout'),
              compact: true,
              icon: w.gridEnabled
                  ? Icons.grid_view_rounded
                  : Icons.crop_square_rounded,
              label: context.tr(
                w.gridEnabled
                    ? 'workspace.layout.grid'
                    : 'workspace.layout.single',
              ),
              trailing: const Icon(Icons.expand_more, size: 16),
              selected: w.gridEnabled && !w.broadcast,
              tooltip: context.tr(
                w.broadcast
                    ? 'workspace.layout.locked'
                    : 'workspace.layout.menu',
              ),
              onPressed: w.broadcast
                  ? null
                  : () => menu.isOpen ? menu.close() : menu.open(),
            ),
            menuChildren: [
              MenuItemButton(
                leadingIcon: const Icon(Icons.crop_square_rounded, size: 18),
                onPressed: w.broadcast ? null : w.showSingle,
                child: Text(context.tr('workspace.layout.single')),
              ),
              MenuItemButton(
                leadingIcon: const Icon(Icons.grid_view_rounded, size: 18),
                onPressed: w.broadcast || w.gridCandidates.isEmpty
                    ? null
                    : () => w.showGrid(),
                child: Text(context.tr('workspace.layout.grid')),
              ),
              const Divider(height: 1),
              MenuItemButton(
                leadingIcon: const Icon(Icons.checklist_rounded, size: 18),
                onPressed: w.broadcast || w.gridCandidates.isEmpty
                    ? null
                    : () => SessionSelectionDialog.show(context, w),
                child: Text(context.tr('workspace.grid.choose')),
              ),
            ],
          ),
      ],
    );
  }
}
