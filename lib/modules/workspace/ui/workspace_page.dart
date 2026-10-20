import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../app/nav_controller.dart';
import '../../../app/theme/app_palette.dart';
import '../../../app/theme/app_theme.dart';
import '../../../l10n/app_localizations.dart';
import '../../../ui_kit/page_header.dart';
import '../../hosts/hosts_controller.dart';
import '../../hosts/ui/host_actions.dart';
import '../../hosts/ui/host_card.dart';
import '../workspace_controller.dart';
import 'session_canvas.dart';
import 'workspace_tab_bar.dart';

/// 工作区：无会话时显示完整页头与最近连接；有会话时页头收缩为一行会话栏，
/// 内容区独立选择单窗口或混合协议网格，广播不改变布局。
class WorkspacePage extends StatelessWidget {
  const WorkspacePage({super.key});

  @override
  Widget build(BuildContext context) {
    final w = context.watch<WorkspaceController>();
    if (w.tabs.isEmpty) return const _EmptyWorkspace();
    return ColoredBox(
      color: context.palette.canvas,
      child: Column(
        children: [
          const WorkspaceTabBar(),
          const Expanded(child: SessionCanvas()),
        ],
      ),
    );
  }
}

/// 无会话时：开始会话的引导与最近连接
class _EmptyWorkspace extends StatelessWidget {
  const _EmptyWorkspace();

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final recent = context.watch<HostsController>().recent(3);
    final nav = context.read<NavController>();
    return PageFrame(
      header: PageHeader(
        title: context.tr('nav.sessions'),
        subtitle: context.tr('workspace.subtitle'),
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const _TerminalIllustration(),
                    const SizedBox(height: 28),
                    Text(
                      context.tr('workspace.empty'),
                      style: TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.w700,
                        color: p.text,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      context.tr('workspace.empty.hint'),
                      style: TextStyle(fontSize: 14, color: p.textMuted),
                    ),
                    const SizedBox(height: 24),
                    FilledButton.icon(
                      style: FilledButton.styleFrom(
                        minimumSize: const Size(200, 48),
                      ),
                      icon: const Icon(
                        Icons.desktop_windows_outlined,
                        size: 18,
                      ),
                      label: Text(context.tr('workspace.go_hosts')),
                      onPressed: () => nav.go(AppPage.hosts),
                    ),
                  ],
                ),
              ),
            ),
          ),
          if (recent.isNotEmpty) ...[
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSizes.pagePadding,
                18,
                24,
                22,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Text(
                        context.tr('workspace.recent'),
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          color: p.text,
                        ),
                      ),
                      const Spacer(),
                      TextButton(
                        style: TextButton.styleFrom(
                          foregroundColor: p.textMuted,
                        ),
                        onPressed: () => nav.go(AppPage.hosts),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(context.tr('workspace.view_all')),
                            const Icon(Icons.chevron_right, size: 18),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    height: 204,
                    child: Row(
                      children: [
                        for (var i = 0; i < 3; i++) ...[
                          if (i > 0) const SizedBox(width: 16),
                          Expanded(
                            child: i < recent.length
                                ? HostCard(
                                    host: recent[i],
                                    showSync: false,
                                    onAction: (a) =>
                                        HostActions.run(context, recent[i], a),
                                  )
                                : const SizedBox.shrink(),
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// 空工作区插画：简化的终端窗口
class _TerminalIllustration extends StatelessWidget {
  const _TerminalIllustration();

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Container(
      width: 200,
      height: 140,
      decoration: BoxDecoration(
        color: p.panel,
        borderRadius: BorderRadius.circular(AppSizes.radiusLarge),
        border: Border.all(color: p.borderStrong),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            height: 28,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            decoration: BoxDecoration(
              color: p.hover,
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(AppSizes.radiusLarge),
              ),
            ),
            child: Row(
              children: [
                for (var i = 0; i < 3; i++)
                  Container(
                    width: 8,
                    height: 8,
                    margin: const EdgeInsets.only(right: 6),
                    decoration: BoxDecoration(
                      color: p.textFaint,
                      shape: BoxShape.circle,
                    ),
                  ),
              ],
            ),
          ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(left: 30),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  '>_',
                  style: TextStyle(
                    fontSize: 34,
                    fontWeight: FontWeight.w700,
                    color: p.accent,
                    fontFamily: 'monospace',
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
