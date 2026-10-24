import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../workspace_controller.dart';
import 'session_canvas.dart';
import 'workspace_start_page.dart';
import 'workspace_tab_bar.dart';

/// 工作区始终保留会话画布，选择主机时仅隐藏，不重建终端和远程桌面。
class WorkspacePage extends StatelessWidget {
  const WorkspacePage({super.key});

  /// 标签栏与开始页共用同一个控制器，切换页面不关闭任何连接。
  @override
  Widget build(BuildContext context) {
    final w = context.watch<WorkspaceController>();
    return Column(
      children: [
        if (w.tabs.isNotEmpty) const WorkspaceTabBar(),
        Expanded(
          key: const ValueKey('workspace-content'),
          child: Stack(
            fit: StackFit.expand,
            children: [
              Visibility(
                visible: !w.showingStartPage,
                maintainState: true,
                child: const SessionCanvas(),
              ),
              Visibility(
                visible: w.showingStartPage,
                maintainState: true,
                child: const WorkspaceStartPage(),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
