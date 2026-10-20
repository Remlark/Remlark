import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../app/theme/app_palette.dart';
import '../../../l10n/app_localizations.dart';
import '../../../ui_kit/app_menu.dart';
import '../../../ui_kit/tags.dart';
import '../../terminal/ui/terminal_themes.dart';
import '../settings_controller.dart';
import 'settings_card.dart';

/// 通用设置：界面语言、外观主题、强调色
class GeneralSection extends StatelessWidget {
  const GeneralSection({super.key});

  @override
  Widget build(BuildContext context) {
    final s = context.watch<SettingsController>();
    return SettingsCard(
      title: context.tr('settings.general'),
      description: context.tr('settings.general.desc'),
      children: [
        SettingsRow(
          label: context.tr('settings.language'),
          description: context.tr('settings.language.desc'),
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
          description: context.tr('settings.theme.desc'),
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
        SettingsRow(
          label: context.tr('settings.accent'),
          description: context.tr('settings.accent.desc'),
          child: Wrap(
            spacing: 12,
            children: [
              for (final a in AccentPreset.values)
                _AccentSwatch(preset: a, selected: s.accent == a.id, onTap: () => s.setAccent(a.id)),
            ],
          ),
        ),
      ],
    );
  }
}

/// 强调色色块
class _AccentSwatch extends StatelessWidget {
  const _AccentSwatch({required this.preset, required this.selected, required this.onTap});

  final AccentPreset preset;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final color = p.isDark ? preset.dark : preset.lightFill;
    return Tooltip(
      message: context.tr('accent.${preset.id}'),
      child: Semantics(
        button: true,
        selected: selected,
        label: context.tr('accent.${preset.id}'),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: onTap,
          child: Container(
            width: 34,
            height: 34,
            padding: const EdgeInsets.all(3),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(color: selected ? p.text : Colors.transparent, width: 2),
            ),
            child: Container(
              decoration: BoxDecoration(color: color, shape: BoxShape.circle),
              child: selected ? Icon(Icons.check, size: 16, color: p.isDark ? preset.darkOn : preset.lightOn) : null,
            ),
          ),
        ),
      ),
    );
  }
}

/// 终端设置：字体、字号、配色、选中即复制、快捷键参考
class TerminalSection extends StatefulWidget {
  const TerminalSection({super.key});

  @override
  State<TerminalSection> createState() => _TerminalSectionState();
}

class _TerminalSectionState extends State<TerminalSection> {
  late final _font = TextEditingController(text: context.read<SettingsController>().terminalFontFamily);

  @override
  void dispose() {
    _font.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = context.watch<SettingsController>();
    final p = context.palette;
    final mac = Theme.of(context).platform == TargetPlatform.macOS;
    final shortcuts = <(List<String>, String)>[
      (mac ? ['⌘', 'C'] : ['Ctrl', 'Shift', 'C'], context.tr('shortcut.copy')),
      (mac ? ['⌘', 'V'] : ['Ctrl', 'Shift', 'V'], context.tr('shortcut.paste')),
      (mac ? ['⌘', 'A'] : ['Ctrl', 'Shift', 'A'], context.tr('shortcut.select_all')),
      ([context.tr('shortcut.right_click')], context.tr('shortcut.right_click.desc')),
    ];
    return SettingsCard(
      title: context.tr('settings.terminal'),
      description: context.tr('settings.terminal.desc'),
      children: [
        SettingsRow(
          label: context.tr('settings.font_family'),
          description: context.tr('settings.font_family.desc'),
          child: SizedBox(
            width: 260,
            child: TextField(
              controller: _font,
              style: const TextStyle(fontFamily: 'monospace'),
              decoration: InputDecoration(hintText: context.tr('settings.font_family.hint')),
              onSubmitted: s.setTerminalFontFamily,
              onTapOutside: (_) => s.setTerminalFontFamily(_font.text),
            ),
          ),
        ),
        SettingsRow(
          label: context.tr('settings.font_size'),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Flexible(
                child: SizedBox(
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
              ),
              Container(
                width: 48,
                height: 36,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: p.input,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: p.borderStrong),
                ),
                child: Text(s.terminalFontSize.toStringAsFixed(0), style: TextStyle(color: p.text)),
              ),
            ],
          ),
        ),
        SettingsRow(
          label: context.tr('settings.terminal_theme'),
          description: context.tr('settings.terminal_theme.desc'),
          child: SizedBox(
            width: 260,
            child: AppDropdown<String>(
              value: s.terminalTheme,
              items: [
                for (final id in TerminalThemesX.ids) AppMenuItem(value: id, label: context.tr('term_theme.$id')),
              ],
              onChanged: (v) => v == null ? null : s.setTerminalTheme(v),
            ),
          ),
        ),
        SettingsRow(
          label: context.tr('settings.copy_on_select'),
          description: context.tr('settings.copy_on_select.desc'),
          child: Switch(value: s.copyOnSelect, onChanged: s.setCopyOnSelect),
        ),
        SettingsRow(
          label: context.tr('settings.shortcuts'),
          description: context.tr('settings.shortcuts.desc'),
          stacked: true,
          child: Wrap(
            spacing: 28,
            runSpacing: 10,
            children: [
              for (final (keys, desc) in shortcuts)
                SizedBox(
                  width: 300,
                  child: Row(
                    children: [
                      for (final k in keys) Padding(padding: const EdgeInsets.only(right: 6), child: KeyCap(k)),
                      const SizedBox(width: 8),
                      Flexible(
                        child: Text(desc, style: TextStyle(fontSize: 13, color: p.textMuted)),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}
