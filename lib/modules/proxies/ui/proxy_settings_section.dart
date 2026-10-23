import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../app/theme/app_palette.dart';
import '../../../l10n/app_localizations.dart';
import '../../../ui_kit/app_dialog.dart';
import '../../../ui_kit/app_menu.dart';
import '../../../utils/ui_utils.dart';
import '../../settings/ui/settings_card.dart';
import '../proxies_controller.dart';
import '../proxy_profile.dart';
import 'proxy_editor_dialog.dart';
import 'proxy_list_row.dart';

/// 代理设置列表；主机编辑器中的“管理代理”复用同一管理界面。
class ProxySettingsSection extends StatefulWidget {
  const ProxySettingsSection({super.key, this.showHeading = true});
  final bool showHeading;

  /// 从主机编辑器管理代理，保留外层未保存的表单。
  static Future<void> showManager(BuildContext context) => showDialog<void>(
    context: context,
    builder: (_) => const ProxySettingsSection(showHeading: false),
  );

  /// 创建搜索和加载状态。
  @override
  State<ProxySettingsSection> createState() => _ProxySettingsSectionState();
}

class _ProxySettingsSectionState extends State<ProxySettingsSection> {
  String _query = '';
  bool _loading = true;
  bool _failed = false;

  /// 进入页面时更新引用数量，覆盖导入、同步及主机删除后的状态。
  @override
  void initState() {
    super.initState();
    _load();
  }

  /// 加载失败显示重试，不用空列表掩盖错误。
  Future<void> _load() async {
    try {
      await context.read<ProxiesController>().load();
      if (mounted) {
        setState(() {
          _loading = false;
          _failed = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _loading = false;
          _failed = true;
        });
      }
    }
  }

  /// 删除未使用的配置；使用中的配置保留并提示引用数量。
  Future<void> _delete(ProxiesController controller, ProxyEntry entry) async {
    final count = controller.usage[entry.uuid] ?? 0;
    if (count > 0) {
      UiUtils.toast(context.tr('proxy.in_use', {'count': count}), error: true);
      return;
    }
    final confirmed = await UiUtils.confirm(
      context,
      title: context.tr('proxy.delete'),
      message: context.tr('proxy.delete_message', {'name': entry.name}),
      danger: true,
    );
    if (!confirmed || !mounted) return;
    try {
      if (!await controller.delete(entry.uuid) && mounted) {
        UiUtils.toast(context.tr('proxy.in_use_changed'), error: true);
      }
    } catch (_) {
      if (mounted) {
        UiUtils.toast(context.tr('proxy.delete_failed'), error: true);
      }
    }
  }

  /// 列表行显示名称、协议、地址及使用情况，小宽度自动改为两行。
  Widget _row(ProxiesController controller, ProxyEntry entry, bool compact) {
    final count = controller.usage[entry.uuid] ?? 0;
    final usage = context.tr(count > 0 ? 'proxy.usage' : 'proxy.unused', {
      'count': count,
    });
    return InkWell(
      onTap: () => ProxyEditorDialog.show(context, controller, entry),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 14),
        decoration: BoxDecoration(
          border: Border(bottom: BorderSide(color: context.palette.border)),
        ),
        child: Row(
          children: [
            Expanded(
              flex: 2,
              child: Text(
                entry.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
            ),
            const SizedBox(width: 12),
            if (!compact)
              SizedBox(
                width: 84,
                child: Text(
                  entry.protocolLabel,
                  style: TextStyle(color: context.palette.textMuted),
                ),
              ),
            Expanded(
              flex: 3,
              child: Tooltip(
                message: entry.endpoint,
                child: Text(
                  compact
                      ? '${entry.protocolLabel} · ${entry.endpoint}\n$usage'
                      : entry.endpoint,
                  maxLines: compact ? 2 : 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 13,
                    color: context.palette.textMuted,
                  ),
                ),
              ),
            ),
            if (!compact) ...[
              const SizedBox(width: 12),
              SizedBox(
                width: 120,
                child: Text(
                  usage,
                  style: TextStyle(
                    fontSize: 13,
                    color: context.palette.textMuted,
                  ),
                ),
              ),
            ],
            AppMenuAnchor<String>(
              builder: (ctx, open) => IconButton(
                tooltip: ctx.tr('proxy.actions'),
                onPressed: open,
                icon: const Icon(Icons.more_horiz),
              ),
              items: (ctx) => [
                AppMenuItem(
                  value: 'edit',
                  label: ctx.tr('common.edit'),
                  icon: Icons.edit_outlined,
                ),
                AppMenuItem(
                  value: 'delete',
                  label: ctx.tr('common.delete'),
                  icon: Icons.delete_outline,
                  danger: true,
                ),
              ],
              onSelected: (value) => value == 'edit'
                  ? ProxyEditorDialog.show(context, controller, entry)
                  : _delete(controller, entry),
            ),
          ],
        ),
      ),
    );
  }

  /// 搜索和添加固定在列表上方，不增加无关的网络功能开关。
  @override
  Widget build(BuildContext context) {
    final controller = context.watch<ProxiesController>();
    final query = _query.trim().toLowerCase();
    final entries = controller.entries
        .where(
          (e) =>
              e.name.toLowerCase().contains(query) ||
              e.endpoint.toLowerCase().contains(query),
        )
        .toList();
    if (!widget.showHeading) return _manager(context, controller, entries);
    final add = FilledButton.icon(
      onPressed: () => ProxyEditorDialog.show(context, controller),
      icon: const Icon(Icons.add, size: 18),
      label: Text(context.tr('proxy.add')),
    );
    final content = <Widget>[
      const SizedBox(height: 18),
      TextField(
        decoration: InputDecoration(
          hintText: context.tr('proxy.search'),
          prefixIcon: const Icon(Icons.search),
        ),
        onChanged: (value) => setState(() => _query = value),
      ),
      const SizedBox(height: 18),
      if (_loading)
        const Center(child: CircularProgressIndicator())
      else if (_failed)
        TextButton(
          onPressed: _load,
          child: Text(context.tr('proxy.load_failed')),
        )
      else if (entries.isEmpty)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 36),
          child: Text(
            context.tr(
              controller.entries.isEmpty ? 'proxy.empty' : 'proxy.no_results',
            ),
            textAlign: TextAlign.center,
            style: TextStyle(color: context.palette.textMuted),
          ),
        )
      else
        LayoutBuilder(
          builder: (context, constraints) => Column(
            children: [
              if (constraints.maxWidth >= 700)
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Row(
                    children: [
                      Expanded(flex: 2, child: Text(context.tr('proxy.name'))),
                      const SizedBox(width: 12),
                      SizedBox(
                        width: 84,
                        child: Text(context.tr('proxy.protocol')),
                      ),
                      Expanded(flex: 3, child: Text(context.tr('proxy.host'))),
                      const SizedBox(width: 12),
                      SizedBox(
                        width: 120,
                        child: Text(context.tr('proxy.usage_title')),
                      ),
                      const SizedBox(width: 48),
                    ],
                  ),
                ),
              for (final entry in entries)
                _row(controller, entry, constraints.maxWidth < 700),
            ],
          ),
        ),
    ];
    return SettingsCard(
      title: context.tr('settings.proxies'),
      description: context.tr('proxy.description'),
      trailing: add,
      children: content,
    );
  }

  /// 紧凑弹窗：一个工具栏、双行列表和固定底栏；单条数据不预留空白。
  Widget _manager(
    BuildContext context,
    ProxiesController controller,
    List<ProxyEntry> entries,
  ) {
    final maxHeight = math.min(
      360.0,
      math.max(80.0, MediaQuery.sizeOf(context).height - 300),
    );
    return AppDialog(
      title: context.tr('settings.proxies'),
      subtitle: context.tr('proxy.manager_hint'),
      width: 640,
      scrollable: false,
      contentPadding: const EdgeInsets.fromLTRB(24, 0, 24, 12),
      content: Column(
        key: const ValueKey('proxy-manager-content'),
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Expanded(
                child: SizedBox(
                  height: 40,
                  child: TextField(
                    decoration: InputDecoration(
                      hintText: context.tr('proxy.search_short'),
                      prefixIcon: const Icon(Icons.search, size: 20),
                    ),
                    onChanged: (value) => setState(() => _query = value),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              FilledButton.icon(
                onPressed: () => ProxyEditorDialog.show(context, controller),
                icon: const Icon(Icons.add, size: 18),
                label: Text(context.tr('proxy.add')),
              ),
            ],
          ),
          const SizedBox(height: 16),
          const Divider(height: 1),
          Flexible(
            child: ConstrainedBox(
              constraints: BoxConstraints(maxHeight: maxHeight),
              child: _loading
                  ? const SizedBox(
                      height: 80,
                      child: Center(child: CircularProgressIndicator()),
                    )
                  : _failed
                  ? TextButton(
                      onPressed: _load,
                      child: Text(context.tr('proxy.load_failed')),
                    )
                  : entries.isEmpty
                  ? Padding(
                      padding: const EdgeInsets.symmetric(vertical: 28),
                      child: Text(
                        context.tr(
                          controller.entries.isEmpty
                              ? 'proxy.empty'
                              : 'proxy.no_results',
                        ),
                        style: TextStyle(color: context.palette.textMuted),
                      ),
                    )
                  : ListView.separated(
                      shrinkWrap: true,
                      itemCount: entries.length,
                      separatorBuilder: (_, _) => const Divider(height: 1),
                      itemBuilder: (_, index) {
                        final entry = entries[index];
                        return ProxyListRow(
                          entry: entry,
                          usage: controller.usage[entry.uuid] ?? 0,
                          onEdit: () => ProxyEditorDialog.show(
                            context,
                            controller,
                            entry,
                          ),
                          onDelete: () => _delete(controller, entry),
                        );
                      },
                    ),
            ),
          ),
        ],
      ),
      actions: [
        Expanded(
          child: Text(
            context.tr('proxy.count', {'count': controller.entries.length}),
            style: TextStyle(fontSize: 12, color: context.palette.textMuted),
          ),
        ),
        OutlinedButton(
          onPressed: () => Navigator.pop(context),
          child: Text(context.tr('common.close')),
        ),
      ],
    );
  }
}
