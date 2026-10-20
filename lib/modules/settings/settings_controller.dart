import 'package:flutter/material.dart';

import 'settings_repository.dart';

/// 应用设置控制器：语言、主题、终端外观等，变化时通知 UI
class SettingsController extends ChangeNotifier {
  SettingsController(this._repo);

  final SettingsRepository _repo;

  Locale _locale = const Locale('zh');
  ThemeMode _themeMode = ThemeMode.dark;
  double _terminalFontSize = 14;
  String _terminalFontFamily = '';
  String _terminalTheme = 'auto';
  bool _copyOnSelect = false;
  String _accent = 'sage';

  Locale get locale => _locale;
  ThemeMode get themeMode => _themeMode;
  double get terminalFontSize => _terminalFontSize;
  String get terminalFontFamily => _terminalFontFamily;
  String get terminalTheme => _terminalTheme;
  bool get copyOnSelect => _copyOnSelect;

  /// 界面强调色预设 id（见 AccentPreset）
  String get accent => _accent;

  static const _keys = [
    'ui.locale',
    'ui.theme',
    'term.fontSize',
    'term.fontFamily',
    'term.theme',
    'term.copyOnSelect',
    'ui.accent',
  ];

  /// 启动时从数据库加载
  Future<void> load() async {
    final m = await _repo.getMany(_keys);
    final lang = m['ui.locale'];
    if (lang != null) {
      _locale = Locale(lang);
    } else {
      // 未设置时跟随系统语言
      final sys = WidgetsBinding.instance.platformDispatcher.locale;
      _locale = Locale(sys.languageCode == 'zh' ? 'zh' : 'en');
    }
    _themeMode = switch (m['ui.theme']) {
      'light' => ThemeMode.light,
      'system' => ThemeMode.system,
      // 未设置时默认深色（设计稿主风格）
      _ => ThemeMode.dark,
    };
    _terminalFontSize = double.tryParse(m['term.fontSize'] ?? '') ?? 14;
    _terminalFontFamily = m['term.fontFamily'] ?? '';
    _terminalTheme = m['term.theme'] ?? 'auto';
    _copyOnSelect = m['term.copyOnSelect'] == '1';
    _accent = m['ui.accent'] ?? 'sage';
    notifyListeners();
  }

  /// 切换语言
  Future<void> setLocale(Locale l) async {
    _locale = l;
    await _repo.set('ui.locale', l.languageCode);
    notifyListeners();
  }

  /// 切换主题模式
  Future<void> setThemeMode(ThemeMode m) async {
    _themeMode = m;
    await _repo.set('ui.theme', m.name);
    notifyListeners();
  }

  /// 设置终端字号
  Future<void> setTerminalFontSize(double v) async {
    _terminalFontSize = v;
    await _repo.set('term.fontSize', '$v');
    notifyListeners();
  }

  /// 设置终端字体
  Future<void> setTerminalFontFamily(String v) async {
    _terminalFontFamily = v;
    await _repo.set('term.fontFamily', v);
    notifyListeners();
  }

  /// 设置终端配色
  Future<void> setTerminalTheme(String v) async {
    _terminalTheme = v;
    await _repo.set('term.theme', v);
    notifyListeners();
  }

  /// 设置“选中即复制”
  Future<void> setCopyOnSelect(bool v) async {
    _copyOnSelect = v;
    await _repo.set('term.copyOnSelect', v ? '1' : '0');
    notifyListeners();
  }

  /// 设置界面强调色
  Future<void> setAccent(String id) async {
    _accent = id;
    await _repo.set('ui.accent', id);
    notifyListeners();
  }
}
