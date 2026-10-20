import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../modules/ai/ui/ai_page.dart';
import '../../modules/hosts/ui/hosts_page.dart';
import '../../modules/keys/ui/keys_page.dart';
import '../../modules/settings/ui/settings_page.dart';
import '../../modules/snippets/ui/snippets_page.dart';
import '../../modules/workspace/ui/workspace_page.dart';
import '../nav_controller.dart';
import '../theme/app_palette.dart';
import 'sidebar.dart';

/// 主界面外壳：左侧应用导航 + 内容区。各页面使用 IndexedStack 保持状态（终端会话不因切页断开）
class HomeShell extends StatelessWidget {
  const HomeShell({super.key});

  @override
  Widget build(BuildContext context) {
    final nav = context.watch<NavController>();
    return Scaffold(
      backgroundColor: context.palette.canvas,
      body: Row(
        children: [
          const Sidebar(),
          Expanded(
            child: IndexedStack(
              index: AppPage.values.indexOf(nav.page),
              children: const [HostsPage(), WorkspacePage(), SnippetsPage(), KeysPage(), AiPage(), SettingsPage()],
            ),
          ),
        ],
      ),
    );
  }
}
