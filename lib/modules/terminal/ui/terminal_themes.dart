import 'package:flutter/material.dart';
import 'package:xterm/xterm.dart';

/// 终端配色方案
class TerminalThemesX {
  TerminalThemesX._();

  /// 跟随界面主题的配色 id（默认）
  static const auto = 'auto';

  /// 可选配色 id
  static const ids = [auto, 'dark', 'light', 'solarized', 'dracula'];

  /// 根据 id 获取配色；[auto] 时按界面亮度在浅色 / 深色之间选择
  static TerminalTheme byId(String id, Brightness uiBrightness) => switch (id) {
    auto => uiBrightness == Brightness.light ? _light : _dark,
    'light' => _light,
    'solarized' => _solarized,
    'dracula' => _dracula,
    _ => _dark,
  };

  static const _dark = TerminalTheme(
    cursor: Color(0xFFE6E6E6),
    selection: Color(0x804A90E2),
    foreground: Color(0xFFD8DEE9),
    background: Color(0xFF131518),
    black: Color(0xFF2E3440),
    red: Color(0xFFE06C75),
    green: Color(0xFF98C379),
    yellow: Color(0xFFE5C07B),
    blue: Color(0xFF61AFEF),
    magenta: Color(0xFFC678DD),
    cyan: Color(0xFF56B6C2),
    white: Color(0xFFD8DEE9),
    brightBlack: Color(0xFF5C6370),
    brightRed: Color(0xFFFF7A85),
    brightGreen: Color(0xFFB5E890),
    brightYellow: Color(0xFFFFD68A),
    brightBlue: Color(0xFF82C4FF),
    brightMagenta: Color(0xFFDDA0F0),
    brightCyan: Color(0xFF7FD4DE),
    brightWhite: Color(0xFFFFFFFF),
    searchHitBackground: Color(0xFFFFFF2B),
    searchHitBackgroundCurrent: Color(0xFF31FF26),
    searchHitForeground: Color(0xFF000000),
  );

  static const _light = TerminalTheme(
    cursor: Color(0xFF333333),
    selection: Color(0x664A90E2),
    foreground: Color(0xFF2E3440),
    background: Color(0xFFFAFAFA),
    black: Color(0xFF000000),
    red: Color(0xFFC91B00),
    green: Color(0xFF00A600),
    yellow: Color(0xFFA68A00),
    blue: Color(0xFF0451A5),
    magenta: Color(0xFFBC05BC),
    cyan: Color(0xFF0598BC),
    white: Color(0xFF888888),
    brightBlack: Color(0xFF666666),
    brightRed: Color(0xFFE74C3C),
    brightGreen: Color(0xFF16A34A),
    brightYellow: Color(0xFFB58900),
    brightBlue: Color(0xFF2563EB),
    brightMagenta: Color(0xFFD946EF),
    brightCyan: Color(0xFF0891B2),
    brightWhite: Color(0xFF444444),
    searchHitBackground: Color(0xFFFFFF2B),
    searchHitBackgroundCurrent: Color(0xFF31FF26),
    searchHitForeground: Color(0xFF000000),
  );

  static const _solarized = TerminalTheme(
    cursor: Color(0xFF93A1A1),
    selection: Color(0x80586E75),
    foreground: Color(0xFF839496),
    background: Color(0xFF002B36),
    black: Color(0xFF073642),
    red: Color(0xFFDC322F),
    green: Color(0xFF859900),
    yellow: Color(0xFFB58900),
    blue: Color(0xFF268BD2),
    magenta: Color(0xFFD33682),
    cyan: Color(0xFF2AA198),
    white: Color(0xFFEEE8D5),
    brightBlack: Color(0xFF586E75),
    brightRed: Color(0xFFCB4B16),
    brightGreen: Color(0xFF93A1A1),
    brightYellow: Color(0xFF657B83),
    brightBlue: Color(0xFF839496),
    brightMagenta: Color(0xFF6C71C4),
    brightCyan: Color(0xFF93A1A1),
    brightWhite: Color(0xFFFDF6E3),
    searchHitBackground: Color(0xFFFFFF2B),
    searchHitBackgroundCurrent: Color(0xFF31FF26),
    searchHitForeground: Color(0xFF000000),
  );

  static const _dracula = TerminalTheme(
    cursor: Color(0xFFF8F8F2),
    selection: Color(0x8044475A),
    foreground: Color(0xFFF8F8F2),
    background: Color(0xFF282A36),
    black: Color(0xFF21222C),
    red: Color(0xFFFF5555),
    green: Color(0xFF50FA7B),
    yellow: Color(0xFFF1FA8C),
    blue: Color(0xFFBD93F9),
    magenta: Color(0xFFFF79C6),
    cyan: Color(0xFF8BE9FD),
    white: Color(0xFFF8F8F2),
    brightBlack: Color(0xFF6272A4),
    brightRed: Color(0xFFFF6E6E),
    brightGreen: Color(0xFF69FF94),
    brightYellow: Color(0xFFFFFFA5),
    brightBlue: Color(0xFFD6ACFF),
    brightMagenta: Color(0xFFFF92DF),
    brightCyan: Color(0xFFA4FFFF),
    brightWhite: Color(0xFFFFFFFF),
    searchHitBackground: Color(0xFFFFFF2B),
    searchHitBackgroundCurrent: Color(0xFF31FF26),
    searchHitForeground: Color(0xFF000000),
  );
}
