import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../l10n/app_localizations.dart';
import '../modules/ai/ui/ai_page.dart';
import '../modules/hosts/ui/hosts_page.dart';
import '../modules/keys/ui/keys_page.dart';
import '../modules/settings/ui/settings_page.dart';
import '../modules/snippets/ui/snippets_page.dart';
import '../modules/workspace/ui/workspace_page.dart';
import '../modules/workspace/workspace_controller.dart';
import 'nav_controller.dart';

/// 主界面外壳：左侧导航栏 + 内容区。会话页使用 IndexedStack 保持终端状态
class HomeShell extends StatelessWidget {
  const HomeShell({super.key});

  @override
  Widget build(BuildContext context) {
    final nav = context.watch<NavController>();
    final sessions = context.select<WorkspaceController, int>((w) => w.tabs.length);
    final pages = AppPage.values;
    final items = <(AppPage, IconData, IconData, String)>[
      (AppPage.hosts, Icons.dns_outlined, Icons.dns, context.tr('nav.hosts')),
      (AppPage.sessions, Icons.terminal_outlined, Icons.terminal, context.tr('nav.sessions')),
      (AppPage.snippets, Icons.bolt_outlined, Icons.bolt, context.tr('nav.snippets')),
      (AppPage.keys, Icons.key_outlined, Icons.key, context.tr('nav.keys')),
      (AppPage.ai, Icons.auto_awesome_outlined, Icons.auto_awesome, context.tr('nav.ai')),
      (AppPage.settings, Icons.settings_outlined, Icons.settings, context.tr('nav.settings')),
    ];
    return Scaffold(
      body: Row(
        children: [
          NavigationRail(
            selectedIndex: pages.indexOf(nav.page),
            onDestinationSelected: (i) => nav.go(pages[i]),
            labelType: NavigationRailLabelType.all,
            minWidth: 72,
            leading: Padding(
              padding: const EdgeInsets.only(top: 8, bottom: 12),
              child: Icon(Icons.hub, color: Theme.of(context).colorScheme.primary, size: 28),
            ),
            destinations: [
              for (final (page, icon, selected, label) in items)
                NavigationRailDestination(
                  icon: page == AppPage.sessions && sessions > 0
                      ? Badge(label: Text('$sessions'), child: Icon(icon))
                      : Icon(icon),
                  selectedIcon: Icon(selected),
                  label: Text(label),
                ),
            ],
          ),
          const VerticalDivider(width: 1),
          Expanded(
            child: IndexedStack(
              index: pages.indexOf(nav.page),
              children: const [HostsPage(), WorkspacePage(), SnippetsPage(), KeysPage(), AiPage(), SettingsPage()],
            ),
          ),
        ],
      ),
    );
  }
}
