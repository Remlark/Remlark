import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../app/nav_controller.dart';
import '../../../app/theme/app_palette.dart';
import '../../../l10n/app_localizations.dart';
import '../../../ui_kit/page_header.dart';
import '../../../ui_kit/panel.dart';
import '../../hosts/hosts_controller.dart';
import '../../hosts/ui/host_actions.dart';
import '../workspace_controller.dart';
import 'workspace_host_card.dart';

/// 工作区开始页：最近连接优先，搜索覆盖全部主机，复用现有协议连接流程。
class WorkspaceStartPage extends StatefulWidget {
  const WorkspaceStartPage({super.key});

  /// 创建页面状态，搜索和浏览范围在返回会话后保留。
  @override
  State<WorkspaceStartPage> createState() => _WorkspaceStartPageState();
}

class _WorkspaceStartPageState extends State<WorkspaceStartPage> {
  String _query = '';
  bool _browseAll = false;

  /// 按最近连接排序并构造搜索结果，不修改主机管理页的筛选状态。
  @override
  Widget build(BuildContext context) {
    final hosts = context.watch<HostsController>();
    final workspace = context.watch<WorkspaceController>();
    final p = context.palette;
    final groupNames = {
      for (final group in hosts.groups) group.uuid: group.name,
    };
    final recent = hosts.recent(hosts.all.length);
    final query = _query.trim().toLowerCase();
    final all = _browseAll || query.isNotEmpty || recent.isEmpty;
    final candidates = all ? List.of(hosts.all) : recent;
    // 未连接主机放在末尾；同一时间按名称稳定排序，避免刷新后卡片跳动。
    candidates.sort((a, b) {
      final time = (b.lastConnectedAt ?? -1).compareTo(a.lastConnectedAt ?? -1);
      return time != 0 ? time : a.name.compareTo(b.name);
    });
    final visible = candidates.where((host) {
      return query.isEmpty ||
          [
            host.name,
            host.address,
            host.username,
            groupNames[host.groupUuid] ?? '',
          ].any((value) => value.toLowerCase().contains(query));
    }).toList();
    return PageFrame(
      header: PageHeader(
        title: context.tr('nav.sessions'),
        subtitle: context.tr('workspace.start.subtitle'),
        actions: [
          if (workspace.tabs.isNotEmpty)
            IconButton(
              onPressed: workspace.resumeSessions,
              tooltip: context.tr('workspace.resume'),
              icon: const Icon(Icons.arrow_back),
            ),
          FilledButton.icon(
            key: const ValueKey('workspace-browse-hosts'),
            onPressed: () => setState(() => _browseAll = !_browseAll),
            icon: Icon(
              _browseAll ? Icons.history : Icons.desktop_windows_outlined,
              size: 18,
            ),
            label: Text(
              context.tr(
                _browseAll ? 'workspace.recent' : 'workspace.go_hosts',
              ),
            ),
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.fromLTRB(28, 16, 24, 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SearchField(
              hint: context.tr('workspace.search'),
              onChanged: (value) => setState(() => _query = value),
            ),
            const SizedBox(height: 18),
            Row(
              children: [
                Text(
                  context.tr(
                    query.isNotEmpty
                        ? 'workspace.results'
                        : all
                        ? 'picker.hosts'
                        : 'workspace.recent',
                  ),
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: p.text,
                  ),
                ),
                const SizedBox(width: 10),
                Text('${visible.length}', style: TextStyle(color: p.textMuted)),
                const SizedBox(width: 16),
                Expanded(
                  child: Text(
                    context.tr('workspace.recent_order'),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 12, color: p.textFaint),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            Expanded(
              child: hosts.loading
                  ? const Center(child: CircularProgressIndicator())
                  : visible.isEmpty
                  ? EmptyState(
                      icon: query.isNotEmpty
                          ? Icons.search_off
                          : Icons.desktop_windows_outlined,
                      title: context.tr(
                        query.isNotEmpty ? 'host.no_match' : 'workspace.empty',
                      ),
                      message: query.isNotEmpty
                          ? null
                          : context.tr('workspace.no_hosts'),
                      action: query.isNotEmpty
                          ? null
                          : OutlinedButton(
                              onPressed: () => context.read<NavController>().go(
                                AppPage.hosts,
                              ),
                              child: Text(context.tr('workspace.manage_hosts')),
                            ),
                    )
                  : LayoutBuilder(
                      builder: (context, box) => GridView.builder(
                        key: const PageStorageKey('workspace-host-grid'),
                        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: ((box.maxWidth + 16) / 316)
                              .floor()
                              .clamp(1, 3),
                          mainAxisExtent: 148,
                          crossAxisSpacing: 16,
                          mainAxisSpacing: 16,
                        ),
                        itemCount: visible.length,
                        itemBuilder: (context, index) {
                          final host = visible[index];
                          return WorkspaceHostCard(
                            key: ValueKey('workspace-host-${host.uuid}'),
                            host: host,
                            groupName:
                                groupNames[host.groupUuid] ??
                                context.tr('group.none'),
                            onAction: (action) =>
                                HostActions.run(context, host, action),
                          );
                        },
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
