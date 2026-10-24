import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../app/theme/app_palette.dart';
import '../../../app/theme/app_theme.dart';
import '../../../l10n/app_localizations.dart';
import '../../../ui_kit/app_table.dart';
import '../../../ui_kit/buttons.dart';
import '../../../ui_kit/page_header.dart';
import '../../../ui_kit/panel.dart';
import '../../../utils/format_utils.dart';
import '../vnc_ssh_config.dart';
import '../hosts_controller.dart';
import 'group_panel.dart';
import 'host_actions.dart';
import 'host_card.dart';
import 'host_editor_dialog.dart';
import 'os_icon.dart';
import 'protocol_tag.dart';
import 'sync_badge.dart';

/// 主机页：页头（新建主机）+ 工具栏（搜索、协议筛选、视图切换）+ 分组导航 + 主机卡片 / 列表
class HostsPage extends StatelessWidget {
  const HostsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final c = context.watch<HostsController>();
    return PageFrame(
      header: PageHeader(
        title: context.tr('nav.hosts'),
        subtitle: context.tr('host.page.subtitle'),
        actions: [_NewHostButton(groupUuid: c.selectedGroupUuid)],
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const _Toolbar(),
          const Divider(height: 1),
          Expanded(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const GroupPanel(),
                Expanded(
                  child: c.listView ? const _HostList() : const _HostGrid(),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// 工具栏：搜索、协议筛选、卡片 / 列表切换
class _Toolbar extends StatelessWidget {
  const _Toolbar();

  @override
  Widget build(BuildContext context) {
    final c = context.watch<HostsController>();
    return Padding(
      padding: const EdgeInsets.fromLTRB(AppSizes.pagePadding, 14, 24, 14),
      child: Row(
        children: [
          // 左侧整体占满剩余宽度，避免 Flexible 的未用空间被留在视图按钮右侧。
          Expanded(
            child: Row(
              children: [
                Flexible(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 360),
                    child: SearchField(
                      hint: context.tr('host.search'),
                      onChanged: c.setSearch,
                    ),
                  ),
                ),
                const SizedBox(width: 16),
                PillChoice<ProtocolFilter>(
                  items: [
                    (ProtocolFilter.all, context.tr('common.all')),
                    (ProtocolFilter.ssh, 'SSH'),
                    (ProtocolFilter.rdp, 'RDP'),
                    (ProtocolFilter.vnc, 'VNC'),
                  ],
                  value: c.protocolFilter,
                  onChanged: c.setProtocolFilter,
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          IconToggleGroup<bool>(
            items: [
              (false, Icons.grid_view_rounded, context.tr('host.view.grid')),
              (true, Icons.view_list_rounded, context.tr('host.view.list')),
            ],
            value: c.listView,
            onChanged: c.setListView,
          ),
        ],
      ),
    );
  }
}

/// 新建主机按钮：协议在编辑弹窗内选择。
class _NewHostButton extends StatelessWidget {
  const _NewHostButton({this.groupUuid});

  final String? groupUuid;

  @override
  Widget build(BuildContext context) {
    return FilledButton.icon(
      onPressed: () => HostEditorDialog.show(context, groupUuid: groupUuid),
      icon: const Icon(Icons.add, size: 18),
      label: Text(context.tr('host.new')),
    );
  }
}

/// 无主机 / 无匹配时的空状态
class _HostsEmpty extends StatelessWidget {
  const _HostsEmpty();

  @override
  Widget build(BuildContext context) {
    final c = context.watch<HostsController>();
    return EmptyState(
      icon: Icons.desktop_windows_outlined,
      title: context.tr(c.all.isEmpty ? 'host.empty' : 'host.no_match'),
      action: c.all.isEmpty
          ? FilledButton.icon(
              icon: const Icon(Icons.add, size: 18),
              onPressed: () => HostEditorDialog.show(
                context,
                groupUuid: c.selectedGroupUuid,
              ),
              label: Text(context.tr('host.new')),
            )
          : null,
    );
  }
}

/// 卡片网格
class _HostGrid extends StatelessWidget {
  const _HostGrid();

  @override
  Widget build(BuildContext context) {
    final c = context.watch<HostsController>();
    if (c.loading) return const Center(child: CircularProgressIndicator());
    final hosts = c.visible;
    if (hosts.isEmpty) return const _HostsEmpty();
    return LayoutBuilder(
      builder: (context, box) {
        final cols = ((box.maxWidth - 40) / 300).floor().clamp(1, 6);
        return GridView.builder(
          padding: const EdgeInsets.all(20),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: cols,
            mainAxisExtent: 204,
            crossAxisSpacing: 16,
            mainAxisSpacing: 16,
          ),
          itemCount: hosts.length,
          itemBuilder: (context, i) {
            final h = hosts[i];
            return HostCard(
              key: ValueKey(h.uuid),
              host: h,
              onAction: (a) => HostActions.run(context, h, a),
            );
          },
        );
      },
    );
  }
}

/// 列表视图：紧凑表格，适合主机较多时浏览
class _HostList extends StatelessWidget {
  const _HostList();

  @override
  Widget build(BuildContext context) {
    final c = context.watch<HostsController>();
    if (c.loading) return const Center(child: CircularProgressIndicator());
    final hosts = c.visible;
    if (hosts.isEmpty) return const _HostsEmpty();
    final p = context.palette;
    return LayoutBuilder(
      builder: (context, box) {
        final wide = box.maxWidth > 760;
        final cols = [
          AppColumn(context.tr('host.name'), flex: 3),
          AppColumn(context.tr('host.address'), flex: 3),
          if (wide) AppColumn(context.tr('host.username'), flex: 2),
          if (wide) AppColumn(context.tr('host.last_connected'), width: 150),
          AppColumn(context.tr('sync.state'), width: wide ? 104 : 40),
          const AppColumn('', width: 152),
        ];
        return Padding(
          padding: const EdgeInsets.all(20),
          child: AppPanel(
            padding: EdgeInsets.zero,
            child: Column(
              children: [
                AppTableHeader(columns: cols),
                Expanded(
                  child: ListView.builder(
                    itemCount: hosts.length,
                    itemBuilder: (context, i) {
                      final h = hosts[i];
                      void act(HostAction a) => HostActions.run(context, h, a);
                      return AppTableRow(
                        key: ValueKey(h.uuid),
                        height: 52,
                        columns: cols,
                        onDoubleTap: h.connectionProtocols.length == 1
                            ? () => act(HostAction.connect)
                            : null,
                        onSecondaryTapUp: (d) =>
                            showHostMenu(context, h, d.globalPosition, act),
                        cells: [
                          Row(
                            children: [
                              OsIcon(host: h, size: 26),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      h.name,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                    FittedBox(
                                      fit: BoxFit.scaleDown,
                                      child: HostProtocolTags(
                                        host: h,
                                        small: true,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                          Text(
                            '${h.address}:${h.port}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontFamily: 'monospace',
                              fontSize: 13,
                            ),
                          ),
                          if (wide)
                            Text(
                              h.username,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          if (wide)
                            Text(
                              h.lastConnectedAt == null
                                  ? '—'
                                  : FormatUtils.dateTime(
                                      DateTime.fromMillisecondsSinceEpoch(
                                        h.lastConnectedAt!,
                                      ),
                                    ),
                              style: TextStyle(
                                fontSize: 13,
                                color: p.textMuted,
                                fontFamily: 'monospace',
                              ),
                            ),
                          SyncBadge(state: h.syncState, withText: wide),
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              HostConnectButtons(
                                host: h,
                                onAction: act,
                                compact: true,
                              ),
                              Builder(
                                builder: (ctx) => GhostIconButton(
                                  icon: Icons.more_horiz,
                                  tooltip: context.tr('common.more'),
                                  onPressed: () {
                                    final b =
                                        ctx.findRenderObject() as RenderBox;
                                    showHostMenu(
                                      context,
                                      h,
                                      b.localToGlobal(
                                        b.size.bottomLeft(Offset.zero),
                                      ),
                                      act,
                                    );
                                  },
                                ),
                              ),
                            ],
                          ),
                        ],
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
