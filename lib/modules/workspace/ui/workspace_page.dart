import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../app/nav_controller.dart';
import '../../../l10n/app_localizations.dart';
import '../../hosts/hosts_controller.dart';
import '../../hosts/ui/os_icon.dart';
import '../../remote_desktop/rdp/rdp_session.dart';
import '../../remote_desktop/ui/rdp_view.dart';
import '../../remote_desktop/ui/vnc_view.dart';
import '../../remote_desktop/vnc/vnc_session.dart';
import '../../terminal/terminal_session.dart';
import '../../terminal/ui/terminal_pane.dart';
import '../../terminal/ui/terminal_tab_view.dart';
import '../session_launcher.dart';
import '../workspace_controller.dart';
import '../workspace_tab.dart';
import 'workspace_tab_bar.dart';

/// 会话工作区：标签栏 + 当前会话视图；平铺模式下同时显示所有终端
class WorkspacePage extends StatelessWidget {
  const WorkspacePage({super.key});

  @override
  Widget build(BuildContext context) {
    final w = context.watch<WorkspaceController>();
    if (w.tabs.isEmpty) return const _EmptyWorkspace();
    final showTiled = w.tiled && w.terminals.length > 1;
    return Column(
      children: [
        const WorkspaceTabBar(),
        if (w.broadcast)
          Container(
            width: double.infinity,
            color: Colors.orange.withValues(alpha: 0.15),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            child: Text(
              context.tr('workspace.broadcast.on', {'n': w.broadcastTargets.length}),
              style: const TextStyle(fontSize: 12),
            ),
          ),
        Expanded(
          child: showTiled
              ? _TiledView(terminals: w.terminals)
              : IndexedStack(
                  index: w.tabs.indexOf(w.active!),
                  children: [for (final t in w.tabs) _TabBody(key: ValueKey(t.id), tab: t)],
                ),
        ),
      ],
    );
  }
}

/// 根据标签类型选择视图
class _TabBody extends StatelessWidget {
  const _TabBody({super.key, required this.tab});

  final WorkspaceTab tab;

  @override
  Widget build(BuildContext context) {
    final t = tab;
    if (t is TerminalSession) return TerminalTabView(session: t);
    if (t is VncSession) return VncView(session: t);
    if (t is RdpSession) return RdpView(session: t);
    return const SizedBox.shrink();
  }
}

/// 平铺视图：网格显示多个终端，点击标题切换焦点
class _TiledView extends StatelessWidget {
  const _TiledView({required this.terminals});

  final List<TerminalSession> terminals;

  @override
  Widget build(BuildContext context) {
    final w = context.read<WorkspaceController>();
    final n = terminals.length;
    final cols = n <= 2 ? n : (n <= 4 ? 2 : 3);
    final rows = (n / cols).ceil();
    final scheme = Theme.of(context).colorScheme;
    return Column(
      children: [
        for (var r = 0; r < rows; r++)
          Expanded(
            child: Row(
              children: [
                for (var c = 0; c < cols; c++)
                  Expanded(
                    child: r * cols + c < n
                        ? Container(
                            margin: const EdgeInsets.all(2),
                            decoration: BoxDecoration(
                              border: Border.all(
                                color: w.active == terminals[r * cols + c] ? scheme.primary : scheme.outlineVariant,
                              ),
                            ),
                            child: Column(
                              children: [
                                GestureDetector(
                                  onTap: () => w.activate(terminals[r * cols + c].id),
                                  child: Container(
                                    color: scheme.surfaceContainerHigh,
                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                    child: Row(
                                      children: [
                                        OsIcon(host: terminals[r * cols + c].host, size: 14),
                                        const SizedBox(width: 6),
                                        Expanded(
                                          child: Text(
                                            terminals[r * cols + c].title,
                                            style: const TextStyle(fontSize: 12),
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                                Expanded(
                                  child: TerminalPane(
                                    key: ValueKey('tile-${terminals[r * cols + c].id}'),
                                    session: terminals[r * cols + c],
                                    autofocus: false,
                                  ),
                                ),
                              ],
                            ),
                          )
                        : const SizedBox.shrink(),
                  ),
              ],
            ),
          ),
      ],
    );
  }
}

/// 无会话时：提示与最近连接
class _EmptyWorkspace extends StatelessWidget {
  const _EmptyWorkspace();

  @override
  Widget build(BuildContext context) {
    final recent = context.watch<HostsController>().recent();
    final theme = Theme.of(context);
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.terminal, size: 56, color: theme.colorScheme.outline),
            const SizedBox(height: 12),
            Text(context.tr('workspace.empty'), style: theme.textTheme.titleMedium),
            const SizedBox(height: 16),
            if (recent.isNotEmpty) ...[
              Align(
                alignment: Alignment.centerLeft,
                child: Text(context.tr('workspace.recent'), style: theme.textTheme.labelLarge),
              ),
              const SizedBox(height: 8),
              for (final h in recent)
                Card(
                  margin: const EdgeInsets.only(bottom: 6),
                  child: ListTile(
                    dense: true,
                    leading: OsIcon(host: h, size: 28),
                    title: Text(h.name),
                    subtitle: Text(h.endpoint),
                    trailing: const Icon(Icons.play_arrow_rounded),
                    onTap: () => SessionLauncher.open(context, h),
                  ),
                ),
            ] else
              FilledButton.tonal(
                onPressed: () => context.read<NavController>().go(AppPage.hosts),
                child: Text(context.tr('workspace.go_hosts')),
              ),
          ],
        ),
      ),
    );
  }
}
