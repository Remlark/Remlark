import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../app/theme/app_palette.dart';
import '../../../l10n/app_localizations.dart';
import '../../../ui_kit/buttons.dart';
import '../../ai/ui/chat_panel.dart';
import '../../snippets/ui/snippet_picker.dart';
import '../../snippets/ui/snippet_runner.dart';
import '../../workspace/ui/session_status_bar.dart';
import '../../workspace/workspace_controller.dart';
import '../../workspace/workspace_tab.dart';
import '../terminal_session.dart';
import 'terminal_pane.dart';
import 'upload_status.dart';

/// 终端侧边面板类型（SFTP 已改为独立工作区标签）
enum SidePanel { none, ai }

/// 单个终端标签的完整视图：工具栏 + 终端 + 可伸缩 AI 侧栏 + 状态栏
class TerminalTabView extends StatefulWidget {
  const TerminalTabView({
    super.key,
    required this.session,
    this.compact = false,
    this.autofocus = true,
  });

  final TerminalSession session;
  final bool compact;
  final bool autofocus;

  @override
  State<TerminalTabView> createState() => _TerminalTabViewState();
}

class _TerminalTabViewState extends State<TerminalTabView> {
  TerminalSession get s => widget.session;

  SidePanel get _panel => s.uiState['panel'] as SidePanel? ?? SidePanel.none;
  double get _panelWidth => s.uiState['panelWidth'] as double? ?? 420;

  void _toggleAi() => setState(
    () => s.uiState['panel'] = _panel == SidePanel.ai
        ? SidePanel.none
        : SidePanel.ai,
  );

  Future<void> _snippets() async {
    final sn = await SnippetPicker.show(context);
    if (sn != null && mounted) await SnippetRunner.run(context, sn, s);
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return ListenableBuilder(
      listenable: s,
      builder: (context, _) => Column(
        children: [
          if (!widget.compact)
            Container(
              height: 48,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Row(
                children: [
                  ToolButton(
                    compact: true,
                    icon: Icons.bolt_outlined,
                    label: context.tr('terminal.snippets'),
                    onPressed: s.state == SessionState.connected
                        ? _snippets
                        : null,
                  ),
                  Container(
                    width: 1,
                    height: 20,
                    margin: const EdgeInsets.symmetric(horizontal: 10),
                    color: p.border,
                  ),
                  ToolButton(
                    compact: true,
                    icon: Icons.folder_open_outlined,
                    label: context.tr('terminal.open_sftp'),
                    onPressed: s.state == SessionState.connected
                        ? () => context.read<WorkspaceController>().openSftp(s)
                        : null,
                  ),
                  const SizedBox(width: 8),
                  ToolButton(
                    compact: true,
                    icon: Icons.auto_awesome_outlined,
                    label: context.tr('terminal.ai'),
                    selected: _panel == SidePanel.ai,
                    onPressed: _toggleAi,
                  ),
                  const SizedBox(width: 8),
                  Semantics(
                    label: context.tr('terminal.reset_text_style'),
                    button: true,
                    child: ToolButton(
                      key: const ValueKey('terminal-reset-text-style'),
                      compact: true,
                      icon: Icons.settings_backup_restore,
                      label: context.tr('terminal.reset_text_style'),
                      tooltip: '${context.tr('terminal.reset_text_style')}\n'
                          '${context.tr('terminal.reset_text_style.desc')}',
                      onPressed: s.resetTextStyle,
                    ),
                  ),
                  const SizedBox(width: 8),
                  ToolButton(
                    compact: true,
                    icon: Icons.refresh,
                    label: context.tr('terminal.reconnect'),
                    onPressed: s.state == SessionState.connecting
                        ? null
                        : s.reconnect,
                  ),
                ],
              ),
            ),
          if (!widget.compact) const Divider(height: 1),
          Expanded(
            key: const ValueKey('terminal-content'),
            // 侧边面板宽度受可用宽度限制，保证终端至少保留 320 像素
            child: LayoutBuilder(
              builder: (context, box) {
                final maxPanel = (box.maxWidth - 320 - 5).clamp(260.0, 900.0);
                final panelWidth = _panelWidth.clamp(260.0, maxPanel);
                return Row(
                  children: [
                    Expanded(
                      child: TerminalPane(
                        session: s,
                        autofocus: widget.autofocus,
                      ),
                    ),
                    if (!widget.compact && _panel == SidePanel.ai) ...[
                      // 可拖动的分隔条，调整侧边面板宽度
                      MouseRegion(
                        cursor: SystemMouseCursors.resizeColumn,
                        child: GestureDetector(
                          onHorizontalDragUpdate: (d) => setState(
                            () => s.uiState['panelWidth'] =
                                (panelWidth - d.delta.dx).clamp(
                                  260.0,
                                  maxPanel,
                                ),
                          ),
                          child: Container(width: 5, color: p.border),
                        ),
                      ),
                      SizedBox(
                        width: panelWidth,
                        child: ChatPanel(
                          key: ValueKey('ai-${s.id}'),
                          session: s,
                        ),
                      ),
                    ],
                  ],
                );
              },
            ),
          ),
          if (!widget.compact)
            SessionStatusBar(
              tab: s,
              detail: s.host.osName,
              // 终端拖拽 / 粘贴上传的进度
              trailing: [if (s.uploads != null) UploadStatus(manager: s.uploads!)],
            ),
        ],
      ),
    );
  }
}
