import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../app/nav_controller.dart';
import '../../../l10n/app_localizations.dart';
import '../../../ui_kit/nav_tile.dart';
import '../../../ui_kit/page_header.dart';
import 'agent_settings_section.dart';
import 'data_section.dart';
import 'general_section.dart';
import 'remote_desktop_section.dart';
import 'sync_settings_section.dart';

/// 设置页：页头 + 左侧分区导航（通用、终端、远程桌面、同步、AI Agent、数据）+ 当前分区内容
class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final nav = context.watch<NavController>();
    final items = <(SettingsSection, IconData, String)>[
      (SettingsSection.general, Icons.tune_rounded, context.tr('settings.general')),
      (SettingsSection.terminal, Icons.terminal_rounded, context.tr('settings.terminal')),
      (SettingsSection.remoteDesktop, Icons.desktop_windows_outlined, context.tr('settings.remote_desktop')),
      (SettingsSection.sync, Icons.sync_rounded, context.tr('settings.sync')),
      (SettingsSection.agents, Icons.auto_awesome_outlined, context.tr('settings.agents')),
      (SettingsSection.data, Icons.storage_rounded, context.tr('settings.data')),
    ];
    final Widget content = switch (nav.settingsSection) {
      SettingsSection.general => const GeneralSection(),
      SettingsSection.terminal => const TerminalSection(),
      SettingsSection.remoteDesktop => const RemoteDesktopSection(),
      SettingsSection.sync => const SyncSettingsSection(),
      SettingsSection.agents => const AgentSettingsSection(),
      SettingsSection.data => const DataSection(),
    };
    return PageFrame(
      header: PageHeader(title: context.tr('nav.settings'), subtitle: context.tr('settings.subtitle')),
      body: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SubNav(
            children: [
              for (final (section, icon, label) in items)
                NavTile(
                  icon: icon,
                  label: label,
                  selected: nav.settingsSection == section,
                  onTap: () => nav.goSettings(section),
                ),
            ],
          ),
          Expanded(
            child: ListView(
              key: ValueKey(nav.settingsSection),
              padding: const EdgeInsets.fromLTRB(32, 24, 32, 24),
              children: [
                Align(
                  alignment: Alignment.topLeft,
                  child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 960), child: content),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
