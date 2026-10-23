import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../app/theme/app_palette.dart';
import '../../../l10n/app_localizations.dart';
import '../../hosts/host_model.dart';
import '../../hosts/ui/host_form.dart';
import '../proxies_controller.dart';
import 'proxy_settings_section.dart';

/// 主机代理选择器：只选择共享配置，管理时保留当前主机表单。
class HostProxySelector extends StatefulWidget {
  const HostProxySelector({super.key, required this.form});
  final HostForm form;

  /// 创建可搜索选择器状态。
  @override
  State<HostProxySelector> createState() => _HostProxySelectorState();
}

class _HostProxySelectorState extends State<HostProxySelector> {
  static const _none = '__no_proxy__';
  static const _legacy = '__current_proxy__';
  bool _failed = false;

  /// 读取最新配置，覆盖进入表单前的同步或导入。
  @override
  void initState() {
    super.initState();
    _load();
  }

  /// 加载失败仍保留表单代理信息，不自动回退为直连。
  Future<void> _load() async {
    try {
      await context.read<ProxiesController>().load();
      if (mounted) setState(() => _failed = false);
    } catch (_) {
      if (mounted) setState(() => _failed = true);
    }
  }

  /// 框内支持搜索，选择后仅更新表单，保存主机时才建立引用。
  @override
  Widget build(BuildContext context) {
    final controller = context.watch<ProxiesController>();
    final form = widget.form;
    final entry = controller.entries
        .where((e) => e.uuid == form.proxyUuid)
        .firstOrNull;
    final legacy = form.proxyUuid == null && form.proxyType != ProxyType.none;
    final selected = form.proxyUuid ?? (legacy ? _legacy : _none);
    final missing = form.proxyUuid != null && entry == null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: DropdownMenu<String>(
                key: ValueKey(
                  controller.entries
                      .map((e) => '${e.uuid}:${e.name}')
                      .join(','),
                ),
                initialSelection: selected,
                expandedInsets: EdgeInsets.zero,
                menuHeight: 280,
                enableFilter: true,
                requestFocusOnTap: true,
                dropdownMenuEntries: [
                  DropdownMenuEntry(
                    value: _none,
                    label: context.tr('proxy.direct'),
                  ),
                  if (legacy)
                    DropdownMenuEntry(
                      value: _legacy,
                      label:
                          '${context.tr('proxy.current')} · ${form.proxyHost.text}:${form.proxyPort.text}',
                    ),
                  if (missing)
                    DropdownMenuEntry(
                      value: selected,
                      label: context.tr('proxy.missing'),
                      enabled: false,
                    ),
                  for (final proxy in controller.entries)
                    DropdownMenuEntry(
                      value: proxy.uuid,
                      label: proxy.name,
                      labelWidget: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            proxy.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          Text(
                            '${proxy.protocolLabel} · ${proxy.endpoint}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 12,
                              color: context.palette.textMuted,
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
                filterCallback: (entries, filter) {
                  final query = filter.trim().toLowerCase();
                  final matches = controller.entries
                      .where(
                        (e) => '${e.name} ${e.endpoint}'.toLowerCase().contains(
                          query,
                        ),
                      )
                      .map((e) => e.uuid)
                      .toSet();
                  return entries
                      .where(
                        (e) =>
                            e.value == _none ||
                            matches.contains(e.value) ||
                            e.label.toLowerCase().contains(query),
                      )
                      .toList();
                },
                onSelected: (uuid) {
                  if (uuid == _none) {
                    form.selectProxy(null, const ProxyConfig());
                  } else {
                    final proxy = controller.entries
                        .where((e) => e.uuid == uuid)
                        .firstOrNull;
                    if (proxy != null) {
                      form.selectProxy(proxy.uuid, proxy.config);
                    }
                  }
                },
              ),
            ),
            const SizedBox(width: 8),
            TextButton.icon(
              onPressed: () => ProxySettingsSection.showManager(context),
              icon: const Icon(Icons.settings_outlined, size: 16),
              label: Text(context.tr('proxy.manage')),
            ),
          ],
        ),
        const SizedBox(height: 8),
        if (_failed)
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton(
              onPressed: _load,
              child: Text(context.tr('proxy.load_failed')),
            ),
          )
        else
          Text(
            entry == null
                ? context.tr(
                    legacy ? 'proxy.current_hint' : 'proxy.select_hint',
                  )
                : '${entry.protocolLabel} · ${entry.endpoint}',
            style: TextStyle(fontSize: 12, color: context.palette.textMuted),
          ),
      ],
    );
  }
}
