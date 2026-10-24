import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../app/theme/app_palette.dart';
import '../../../app/theme/app_theme.dart';
import '../../../l10n/app_localizations.dart';
import '../../../ui_kit/buttons.dart';
import '../../hosts/ui/os_icon.dart';
import '../../hosts/ui/protocol_tag.dart';
import '../workspace_controller.dart';
import '../workspace_tab.dart';
import 'workspace_actions.dart';

/// 单行会话栏：左侧管理会话，右侧独立广播与布局，不再用广播条替换标签。
class WorkspaceTabBar extends StatelessWidget {
  const WorkspaceTabBar({super.key});

  @override
  Widget build(BuildContext context) {
    final w = context.watch<WorkspaceController>();
    final p = context.palette;
    return Container(
      height: 56,
      decoration: BoxDecoration(
        color: p.canvas,
        border: Border(
          bottom: BorderSide(
            color: w.broadcast ? p.warning.withValues(alpha: 0.5) : p.border,
          ),
        ),
      ),
      child: Row(
        children: [
          Padding(
            padding: const EdgeInsets.only(left: 20, right: 16),
            child: Text(
              context.tr('nav.sessions'),
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: p.text,
              ),
            ),
          ),
          Container(width: 1, height: 22, color: p.borderStrong),
          const SizedBox(width: 8),
          const Expanded(child: _Tabs()),
          const SizedBox(width: 16),
          const WorkspaceActions(),
          const SizedBox(width: 16),
        ],
      ),
    );
  }
}

/// 标签页列表与新建会话，右侧留白由父级占满。
class _Tabs extends StatelessWidget {
  const _Tabs();

  @override
  Widget build(BuildContext context) {
    final w = context.watch<WorkspaceController>();
    return Row(
      children: [
        Flexible(
          child: ReorderableListView(
            scrollDirection: Axis.horizontal,
            buildDefaultDragHandles: false,
            shrinkWrap: true,
            padding: const EdgeInsets.symmetric(vertical: 10),
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
                  child: _TabChip(
                    tab: w.tabs[i],
                    active: !w.showingStartPage && w.active == w.tabs[i],
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(width: 4),
        ToolButton(
          compact: true,
          selected: w.showingStartPage,
          icon: Icons.add,
          label: context.tr('workspace.new_session'),
          tooltip: context.tr('workspace.new_session'),
          onPressed: w.showStartPage,
        ),
      ],
    );
  }
}

/// 单个会话标签：系统图标、名称、协议、未连接时的状态点、关闭
class _TabChip extends StatefulWidget {
  const _TabChip({required this.tab, required this.active});

  final WorkspaceTab tab;
  final bool active;

  @override
  State<_TabChip> createState() => _TabChipState();
}

class _TabChipState extends State<_TabChip> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final w = context.read<WorkspaceController>();
    final p = context.palette;
    final tab = widget.tab;
    final active = widget.active;
    final dot = switch (tab.state) {
      SessionState.connecting => p.warning,
      SessionState.connected => null,
      SessionState.disconnected => p.textFaint,
      SessionState.failed => p.danger,
    };
    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        onTap: () => w.selectTab(tab.id),
        // 鼠标中键关闭
        onTertiaryTapUp: (_) => w.closeTab(tab),
        child: Container(
          margin: const EdgeInsets.only(right: 6),
          padding: const EdgeInsets.only(left: 10, right: 4),
          constraints: const BoxConstraints(maxWidth: 240),
          decoration: BoxDecoration(
            color: active ? p.panel : (_hover ? p.hover : Colors.transparent),
            borderRadius: BorderRadius.circular(AppSizes.radius),
            border: Border.all(
              color: active ? p.accent.withValues(alpha: 0.6) : p.border,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              tab.kindLabel == 'SFTP'
                  ? Icon(
                      Icons.folder_open_outlined,
                      size: 17,
                      color: p.textMuted,
                    )
                  : OsIcon(host: tab.host, size: 18),
              const SizedBox(width: 8),
              if (dot != null) ...[
                Container(
                  width: 7,
                  height: 7,
                  decoration: BoxDecoration(color: dot, shape: BoxShape.circle),
                ),
                const SizedBox(width: 6),
              ],
              Flexible(
                child: Text(
                  tab.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 13.5,
                    color: active ? p.text : p.textMuted,
                    fontWeight: active ? FontWeight.w600 : FontWeight.w500,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              ProtocolTag(tab.kindLabel, small: true),
              GhostIconButton(
                icon: Icons.close,
                size: 26,
                tooltip: context.tr('workspace.close_tab'),
                onPressed: () => w.closeTab(tab),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
