import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../app/theme/app_palette.dart';
import '../../../l10n/app_localizations.dart';
import '../../../ui_kit/app_dialog.dart';
import '../../../ui_kit/nav_tile.dart';
import '../host_model.dart';
import '../hosts_controller.dart';

/// 跳板服务器选择器：分组与搜索保持独立滚动，确认后才追加到跳板链。
class JumpHostPickerDialog extends StatefulWidget {
  const JumpHostPickerDialog({
    super.key,
    required this.candidates,
    required this.groups,
  });

  final List<HostEntry> candidates;
  final List<GroupEntry> groups;

  /// 打开单选对话框；取消、关闭和 Escape 均返回空值。
  static Future<String?> show(
    BuildContext context, {
    required List<HostEntry> candidates,
    required List<GroupEntry> groups,
  }) => showDialog<String>(
    context: context,
    builder: (_) =>
        JumpHostPickerDialog(candidates: candidates, groups: groups),
  );

  /// 创建对话框的筛选和选择状态。
  @override
  State<JumpHostPickerDialog> createState() => _JumpHostPickerDialogState();
}

class _JumpHostPickerDialogState extends State<JumpHostPickerDialog> {
  final _search = TextEditingController();
  final _groupScroll = ScrollController();
  final _hostScroll = ScrollController();
  String? _group;
  String? _selected;

  /// 释放搜索框与两个独立列表的滚动控制器。
  @override
  void dispose() {
    _search.dispose();
    _groupScroll.dispose();
    _hostScroll.dispose();
    super.dispose();
  }

  /// 分组统计只包含可用候选；统计不随搜索词变化。
  bool _inGroup(HostEntry host, String? group) => switch (group) {
    null => true,
    HostsController.ungrouped => host.groupUuid == null,
    _ => host.groupUuid == group,
  };

  /// 切换分组或搜索词时清除旧选择，防止添加不可见的服务器。
  void _filterChanged({String? group, bool changeGroup = false}) {
    setState(() {
      if (changeGroup) _group = group;
      _selected = null;
    });
    if (_hostScroll.hasClients) _hostScroll.jumpTo(0);
  }

  /// 组合当前分组与忽略大小写的名称、端点搜索。
  List<HostEntry> get _visible {
    final query = _search.text.trim().toLowerCase();
    return widget.candidates.where((host) {
      return _inGroup(host, _group) &&
          (query.isEmpty ||
              host.name.toLowerCase().contains(query) ||
              host.endpoint.toLowerCase().contains(query));
    }).toList();
  }

  /// 显示当前分组名，未知分组回退到全部服务器。
  String _groupName(BuildContext context) {
    if (_group == null) return context.tr('host.jump.all');
    if (_group == HostsController.ungrouped) return context.tr('group.none');
    return widget.groups.where((g) => g.uuid == _group).firstOrNull?.name ??
        context.tr('host.jump.all');
  }

  /// 固定标题、搜索和底栏；列表区域根据可用窗口高度缩放。
  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final visible = _visible;
    final selected = widget.candidates
        .where((h) => h.uuid == _selected)
        .firstOrNull;
    final height = math.min(
      420.0,
      math.max(160.0, MediaQuery.sizeOf(context).height - 230),
    );
    return AppDialog(
      title: context.tr('host.jump.add'),
      subtitle: context.tr('host.jump.picker_hint'),
      width: 880,
      scrollable: false,
      contentPadding: EdgeInsets.zero,
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Divider(height: 1),
          Flexible(
            child: SizedBox(
              height: height,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  SizedBox(width: 216, child: _groups(context)),
                  const VerticalDivider(width: 1),
                  Expanded(child: _hosts(context, visible)),
                ],
              ),
            ),
          ),
        ],
      ),
      actions: [
        Expanded(
          child: Text.rich(
            TextSpan(
              text: selected == null
                  ? context.tr('host.jump.choose')
                  : '${context.tr('host.jump.selected')}  ',
              style: TextStyle(color: p.textMuted, fontSize: 13),
              children: [
                if (selected != null)
                  TextSpan(
                    text: selected.name,
                    style: TextStyle(
                      color: p.accent,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
              ],
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        OutlinedButton(
          onPressed: () => Navigator.pop(context),
          child: Text(context.tr('common.cancel')),
        ),
        FilledButton(
          onPressed: selected == null
              ? null
              : () => Navigator.pop(context, selected.uuid),
          child: Text(context.tr('host.jump.confirm')),
        ),
      ],
    );
  }

  /// 左侧目录沿用现有单层分组，不改变主机页的分组选择。
  Widget _groups(BuildContext context) {
    return Scrollbar(
      controller: _groupScroll,
      child: ListView(
        controller: _groupScroll,
        padding: const EdgeInsets.all(10),
        children: [
          _groupTile(context, null, context.tr('host.jump.all')),
          for (final group in widget.groups)
            _groupTile(context, group.uuid, group.name),
          // “未分组”是虚拟入口，仅在有可选服务器时显示。
          if (widget.candidates.any((host) => host.groupUuid == null))
            _groupTile(
              context,
              HostsController.ungrouped,
              context.tr('group.none'),
            ),
        ],
      ),
    );
  }

  /// 每个分组展示可选数量，并为长分组名提供完整提示。
  Widget _groupTile(BuildContext context, String? id, String name) {
    final count = widget.candidates.where((h) => _inGroup(h, id)).length;
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Tooltip(
        message: name,
        child: NavTile(
          icon: Icons.folder_outlined,
          label: name,
          selected: _group == id,
          trailing: Text('$count'),
          onTap: () => _filterChanged(group: id, changeGroup: true),
        ),
      ),
    );
  }

  /// 右侧搜索栏固定，结果使用懒加载列表，避免主机过多撑高弹窗。
  Widget _hosts(BuildContext context, List<HostEntry> visible) {
    final p = context.palette;
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextField(
            controller: _search,
            autofocus: true,
            decoration: InputDecoration(
              hintText: context.tr('host.jump.search'),
              prefixIcon: const Icon(Icons.search, size: 20),
              suffixIcon: _search.text.isEmpty
                  ? null
                  : IconButton(
                      tooltip: context.tr('host.jump.clear_search'),
                      icon: const Icon(Icons.close, size: 18),
                      onPressed: () {
                        _search.clear();
                        _filterChanged();
                      },
                    ),
            ),
            onChanged: (_) => _filterChanged(),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: Text(
                  _groupName(context),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 12),
              Text(
                context.tr('host.jump.count', {'count': visible.length}),
                style: TextStyle(color: p.textMuted),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Expanded(
            child: visible.isEmpty
                ? Center(
                    child: Text(
                      context.tr(
                        widget.candidates.isEmpty
                            ? 'host.jump.no_candidates'
                            : 'host.jump.no_results',
                      ),
                      textAlign: TextAlign.center,
                      style: TextStyle(color: p.textMuted),
                    ),
                  )
                : RadioGroup<String>(
                    groupValue: _selected,
                    onChanged: (uuid) => setState(() => _selected = uuid),
                    child: Scrollbar(
                      controller: _hostScroll,
                      thumbVisibility: true,
                      child: ListView.separated(
                        controller: _hostScroll,
                        itemCount: visible.length,
                        separatorBuilder: (_, _) => const Divider(height: 1),
                        itemBuilder: (context, index) =>
                            _hostRow(context, visible[index]),
                      ),
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  /// 整行可单选，名称和端点截断时仍可悬停查看全文。
  Widget _hostRow(BuildContext context, HostEntry host) {
    return Material(
      color: _selected == host.uuid
          ? context.palette.accentSoft
          : Colors.transparent,
      borderRadius: BorderRadius.circular(8),
      child: Tooltip(
        message: '${host.name}\n${host.endpoint}',
        child: RadioListTile<String>(
          value: host.uuid,
          dense: true,
          contentPadding: const EdgeInsets.only(right: 8),
          title: Text(
            host.name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 14),
          ),
          subtitle: Text(
            host.endpoint,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 12,
              fontFamily: 'monospace',
              color: context.palette.textMuted,
            ),
          ),
        ),
      ),
    );
  }
}
