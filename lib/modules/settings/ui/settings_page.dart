import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../l10n/app_localizations.dart';
import '../../terminal/ui/terminal_themes.dart';
import '../settings_controller.dart';
import 'agent_settings_section.dart';
import 'data_section.dart';
import 'settings_card.dart';
import 'sync_settings_section.dart';

/// 设置页：通用、终端、同步、AI Agent、数据
class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 20),
      children: [
        Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 820),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(context.tr('nav.settings'), style: Theme.of(context).textTheme.titleLarge),
                const SizedBox(height: 16),
                const _GeneralSection(),
                const _TerminalSection(),
                const SyncSettingsSection(),
                const AgentSettingsSection(),
                const DataSection(),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _GeneralSection extends StatelessWidget {
  const _GeneralSection();

  @override
  Widget build(BuildContext context) {
    final s = context.watch<SettingsController>();
    return SettingsCard(
      title: context.tr('settings.general'),
      children: [
        SettingsRow(
          label: context.tr('settings.language'),
          child: SegmentedButton<String>(
            showSelectedIcon: false,
            segments: const [
              ButtonSegment(value: 'zh', label: Text('简体中文')),
              ButtonSegment(value: 'en', label: Text('English')),
            ],
            selected: {s.locale.languageCode},
            onSelectionChanged: (v) => s.setLocale(Locale(v.first)),
          ),
        ),
        SettingsRow(
          label: context.tr('settings.theme'),
          child: SegmentedButton<ThemeMode>(
            showSelectedIcon: false,
            segments: [
              ButtonSegment(value: ThemeMode.system, label: Text(context.tr('settings.theme.system'))),
              ButtonSegment(value: ThemeMode.light, label: Text(context.tr('settings.theme.light'))),
              ButtonSegment(value: ThemeMode.dark, label: Text(context.tr('settings.theme.dark'))),
            ],
            selected: {s.themeMode},
            onSelectionChanged: (v) => s.setThemeMode(v.first),
          ),
        ),
      ],
    );
  }
}

class _TerminalSection extends StatefulWidget {
  const _TerminalSection();

  @override
  State<_TerminalSection> createState() => _TerminalSectionState();
}

class _TerminalSectionState extends State<_TerminalSection> {
  late final _font = TextEditingController(text: context.read<SettingsController>().terminalFontFamily);

  @override
  void dispose() {
    _font.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = context.watch<SettingsController>();
    return SettingsCard(
      title: context.tr('settings.terminal'),
      children: [
        SettingsRow(
          label: context.tr('settings.font_size'),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                width: 200,
                child: Slider(
                  min: 10,
                  max: 24,
                  divisions: 14,
                  value: s.terminalFontSize.clamp(10, 24),
                  label: s.terminalFontSize.toStringAsFixed(0),
                  onChanged: s.setTerminalFontSize,
                ),
              ),
              Text(s.terminalFontSize.toStringAsFixed(0)),
            ],
          ),
        ),
        SettingsRow(
          label: context.tr('settings.font_family'),
          child: SizedBox(
            width: 240,
            child: TextField(
              controller: _font,
              decoration: InputDecoration(hintText: context.tr('settings.font_family.hint')),
              onSubmitted: s.setTerminalFontFamily,
              onTapOutside: (_) => s.setTerminalFontFamily(_font.text),
            ),
          ),
        ),
        SettingsRow(
          label: context.tr('settings.terminal_theme'),
          child: DropdownButton<String>(
            value: s.terminalTheme,
            items: [
              for (final id in TerminalThemesX.ids)
                DropdownMenuItem(value: id, child: Text(context.tr('term_theme.$id'))),
            ],
            onChanged: (v) => v == null ? null : s.setTerminalTheme(v),
          ),
        ),
        SettingsRow(
          label: context.tr('settings.copy_on_select'),
          child: Switch(value: s.copyOnSelect, onChanged: s.setCopyOnSelect),
        ),
        Padding(
          padding: const EdgeInsets.only(top: 6),
          child: Text(context.tr('settings.shortcuts_hint'), style: Theme.of(context).textTheme.bodySmall),
        ),
      ],
    );
  }
}
