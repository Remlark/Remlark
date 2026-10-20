import 'package:flutter/material.dart';

import '../../../l10n/app_localizations.dart';
import '../../../ui_kit/app_dialog.dart';
import '../../hosts/ui/os_icon.dart';
import '../../hosts/ui/protocol_tag.dart';
import '../workspace_controller.dart';

/// 为网格或广播选择已打开的会话；两类选择互不影响。
class SessionSelectionDialog extends StatefulWidget {
  const SessionSelectionDialog({
    super.key,
    required this.workspace,
    this.broadcast = false,
  });
  final WorkspaceController workspace;
  final bool broadcast;

  /// 显示选择框，确认时再次由控制器过滤已关闭的会话。
  static Future<void> show(
    BuildContext context,
    WorkspaceController workspace, {
    bool broadcast = false,
  }) async {
    final ids = await showDialog<List<String>>(
      context: context,
      builder: (_) =>
          SessionSelectionDialog(workspace: workspace, broadcast: broadcast),
    );
    if (ids == null) return;
    if (broadcast) {
      workspace.startBroadcast(ids: ids);
    } else {
      workspace.showGrid(ids);
    }
  }

  @override
  State<SessionSelectionDialog> createState() => _SessionSelectionDialogState();
}

class _SessionSelectionDialogState extends State<SessionSelectionDialog> {
  late final Set<String> _selected;

  /// 首次选择默认勾选可用会话；已有选择则恢复，打开弹窗不立即更改状态。
  @override
  void initState() {
    super.initState();
    final w = widget.workspace;
    final saved = widget.broadcast ? w.broadcastIds : w.gridIds;
    final candidates = widget.broadcast ? w.terminals : w.gridCandidates;
    _selected = (saved.isEmpty ? candidates.map((t) => t.id).take(9) : saved)
        .toSet();
  }

  /// 动态读取候选项，以兼容弹窗打开期间关闭的会话。
  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.workspace,
    builder: (context, _) {
      final w = widget.workspace;
      final candidates = widget.broadcast ? w.terminals : w.gridCandidates;
      final validIds = candidates.map((t) => t.id).toSet();
      final selected = _selected.intersection(validIds);
      final limit = widget.broadcast
          ? WorkspaceController.maxBroadcast
          : WorkspaceController.maxGrid;
      return AppDialog(
        title: context.tr(
          widget.broadcast
              ? 'workspace.broadcast.choose'
              : 'workspace.grid.choose',
        ),
        width: 480,
        scrollable: false,
        content: SizedBox(
          height: 340,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                context.tr(
                  widget.broadcast
                      ? 'workspace.broadcast.choose_hint'
                      : 'workspace.grid.choose_hint',
                ),
              ),
              const SizedBox(height: 12),
              Expanded(
                child: ListView(
                  children: [
                    for (final t in candidates)
                      CheckboxListTile(
                        contentPadding: EdgeInsets.zero,
                        secondary: OsIcon(host: t.host, size: 26),
                        title: Row(
                          children: [
                            Expanded(
                              child: Text(
                                t.title,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            const SizedBox(width: 8),
                            ProtocolTag(t.kindLabel, small: true),
                          ],
                        ),
                        subtitle: Text(
                          t.host.endpoint,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        value: selected.contains(t.id),
                        onChanged:
                            !selected.contains(t.id) && selected.length >= limit
                            ? null
                            : (v) => setState(() {
                                _selected.removeWhere(
                                  (id) => !validIds.contains(id),
                                );
                                v == true
                                    ? _selected.add(t.id)
                                    : _selected.remove(t.id);
                              }),
                      ),
                  ],
                ),
              ),
              Text(
                context.tr('workspace.selection.count', {
                  'n': selected.length,
                  'max': limit,
                }),
              ),
            ],
          ),
        ),
        actions: [
          OutlinedButton(
            onPressed: () => Navigator.pop(context),
            child: Text(context.tr('common.cancel')),
          ),
          FilledButton(
            onPressed: selected.isEmpty
                ? null
                : () => Navigator.pop(context, selected.toList()),
            child: Text(
              context.tr(
                widget.broadcast
                    ? 'workspace.broadcast.apply'
                    : 'workspace.grid.apply',
              ),
            ),
          ),
        ],
      );
    },
  );
}
