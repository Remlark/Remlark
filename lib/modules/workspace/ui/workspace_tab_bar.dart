import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../l10n/app_localizations.dart';
import '../../hosts/ui/os_icon.dart';
import '../../terminal/terminal_session.dart';
import '../workspace_controller.dart';
import '../workspace_tab.dart';

/// 会话标签栏：系统图标、标题、状态点、广播勾选、关闭；右侧为平铺与广播开关
class WorkspaceTabBar extends StatelessWidget {
  const WorkspaceTabBar({super.key});

  @override
  Widget build(BuildContext context) {
    final w = context.watch<WorkspaceController>();
    final scheme = Theme.of(context).colorScheme;
    return Container(
      height: 42,
      color: scheme.surfaceContainerLow,
      child: Row(
        children: [
          Expanded(
            child: ReorderableListView(
              scrollDirection: Axis.horizontal,
              buildDefaultDragHandles: false,
              onReorderItem: (a, b) {
                final t = w.tabs.removeAt(a);
                w.tabs.insert(b, t);
                w.activate(t.id);
              },
              children: [
                for (var i = 0; i < w.tabs.length; i++)
                  ReorderableDragStartListener(
                    key: ValueKey(w.tabs[i].id),
                    index: i,
                    child: _TabChip(tab: w.tabs[i], active: w.active == w.tabs[i]),
                  ),
              ],
            ),
          ),
          if (w.terminals.length > 1) ...[
            Tooltip(
              message: context.tr('workspace.tiled'),
              child: IconButton(
                isSelected: w.tiled,
                icon: const Icon(Icons.grid_view, size: 18),
                selectedIcon: Icon(Icons.grid_view, size: 18, color: scheme.primary),
                onPressed: () => w.setTiled(!w.tiled),
              ),
            ),
            Tooltip(
              message: context.tr('workspace.broadcast'),
              child: IconButton(
                isSelected: w.broadcast,
                icon: const Icon(Icons.campaign_outlined, size: 18),
                selectedIcon: const Icon(Icons.campaign, size: 18, color: Colors.orange),
                onPressed: () => w.setBroadcast(!w.broadcast),
              ),
            ),
          ],
          const SizedBox(width: 6),
        ],
      ),
    );
  }
}

class _TabChip extends StatelessWidget {
  const _TabChip({required this.tab, required this.active});

  final WorkspaceTab tab;
  final bool active;

  @override
  Widget build(BuildContext context) {
    final w = context.read<WorkspaceController>();
    final scheme = Theme.of(context).colorScheme;
    final dot = switch (tab.state) {
      SessionState.connecting => Colors.amber,
      SessionState.connected => Colors.green,
      SessionState.disconnected => Colors.grey,
      SessionState.failed => Colors.red,
    };
    final isTerm = tab is TerminalSession;
    return GestureDetector(
      onTap: () => w.activate(tab.id),
      onTertiaryTapUp: (_) => w.closeTab(tab),
      child: Container(
        margin: const EdgeInsets.only(left: 4, top: 5, bottom: 0),
        padding: const EdgeInsets.only(left: 10, right: 2),
        constraints: const BoxConstraints(maxWidth: 240),
        decoration: BoxDecoration(
          color: active ? Theme.of(context).scaffoldBackgroundColor : Colors.transparent,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(8)),
          border: active ? Border(top: BorderSide(color: scheme.primary, width: 2)) : null,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (w.broadcast && isTerm)
              SizedBox(
                width: 22,
                child: Checkbox(
                  visualDensity: VisualDensity.compact,
                  value: w.broadcastTargets.contains(tab.id),
                  onChanged: (_) => w.toggleBroadcastTarget(tab.id),
                ),
              ),
            OsIcon(host: tab.host, size: 18),
            const SizedBox(width: 6),
            Container(
              width: 7,
              height: 7,
              decoration: BoxDecoration(color: dot, shape: BoxShape.circle),
            ),
            const SizedBox(width: 6),
            Flexible(child: Text(tab.title, maxLines: 1, overflow: TextOverflow.ellipsis)),
            IconButton(
              visualDensity: VisualDensity.compact,
              iconSize: 14,
              icon: const Icon(Icons.close),
              onPressed: () => w.closeTab(tab),
            ),
          ],
        ),
      ),
    );
  }
}
