import 'package:flutter/material.dart';

import '../../../l10n/app_localizations.dart';
import '../../ai/ui/chat_panel.dart';
import '../../sftp/ui/sftp_panel.dart';
import '../../snippets/ui/snippet_picker.dart';
import '../../snippets/ui/snippet_runner.dart';
import '../../workspace/workspace_tab.dart';
import '../terminal_session.dart';
import 'terminal_pane.dart';

/// 终端侧边面板类型
enum SidePanel { none, sftp, ai }

/// 单个终端标签的完整视图：工具栏 + 终端 + 可切换的侧边面板（SFTP / AI）+ 状态栏
class TerminalTabView extends StatefulWidget {
  const TerminalTabView({super.key, required this.session});

  final TerminalSession session;

  @override
  State<TerminalTabView> createState() => _TerminalTabViewState();
}

class _TerminalTabViewState extends State<TerminalTabView> {
  TerminalSession get s => widget.session;

  SidePanel get _panel => s.uiState['panel'] as SidePanel? ?? SidePanel.none;
  double get _panelWidth => s.uiState['panelWidth'] as double? ?? 400;

  void _toggle(SidePanel p) => setState(() => s.uiState['panel'] = _panel == p ? SidePanel.none : p);

  Future<void> _snippets() async {
    final sn = await SnippetPicker.show(context);
    if (sn != null && mounted) await SnippetRunner.run(context, sn, s);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ListenableBuilder(
      listenable: s,
      builder: (context, _) => Column(
        children: [
          Container(
            height: 38,
            padding: const EdgeInsets.symmetric(horizontal: 6),
            child: Row(
              children: [
                _ToolButton(icon: Icons.bolt, label: context.tr('terminal.snippets'), onPressed: _snippets),
                _ToolButton(
                  icon: Icons.folder_outlined,
                  label: 'SFTP',
                  selected: _panel == SidePanel.sftp,
                  onPressed: s.state == SessionState.connected ? () => _toggle(SidePanel.sftp) : null,
                ),
                _ToolButton(
                  icon: Icons.auto_awesome_outlined,
                  label: 'AI',
                  selected: _panel == SidePanel.ai,
                  onPressed: () => _toggle(SidePanel.ai),
                ),
                const Spacer(),
                if (s.host.osName != null)
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: Text(
                      s.host.osName!,
                      style: theme.textTheme.labelSmall?.copyWith(color: theme.colorScheme.outline),
                    ),
                  ),
                Text(s.host.endpoint, style: theme.textTheme.labelSmall?.copyWith(color: theme.colorScheme.outline)),
                IconButton(
                  tooltip: context.tr('terminal.reconnect'),
                  visualDensity: VisualDensity.compact,
                  icon: const Icon(Icons.refresh, size: 16),
                  onPressed: s.state == SessionState.connecting ? null : s.reconnect,
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: Row(
              children: [
                Expanded(child: TerminalPane(session: s)),
                if (_panel != SidePanel.none) ...[
                  // 可拖动的分隔条，调整侧边面板宽度
                  MouseRegion(
                    cursor: SystemMouseCursors.resizeColumn,
                    child: GestureDetector(
                      onHorizontalDragUpdate: (d) =>
                          setState(() => s.uiState['panelWidth'] = (_panelWidth - d.delta.dx).clamp(280.0, 900.0)),
                      child: Container(width: 5, color: theme.dividerColor),
                    ),
                  ),
                  SizedBox(
                    width: _panelWidth,
                    child: _panel == SidePanel.sftp
                        ? SftpPanel(key: ValueKey('sftp-${s.id}-${s.sftp.hashCode}'), session: s)
                        : ChatPanel(key: ValueKey('ai-${s.id}'), session: s),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ToolButton extends StatelessWidget {
  const _ToolButton({required this.icon, required this.label, this.onPressed, this.selected = false});

  final IconData icon;
  final String label;
  final VoidCallback? onPressed;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(right: 2),
      child: TextButton.icon(
        style: TextButton.styleFrom(
          visualDensity: VisualDensity.compact,
          backgroundColor: selected ? scheme.primaryContainer : null,
        ),
        onPressed: onPressed,
        icon: Icon(icon, size: 16),
        label: Text(label),
      ),
    );
  }
}
