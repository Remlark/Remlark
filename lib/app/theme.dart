import 'package:flutter/material.dart';

/// 应用主题：Material 3，简洁的桌面风格
class AppTheme {
  AppTheme._();

  static const _seed = Color(0xFF3B6FE0);

  /// 构造主题
  static ThemeData build(Brightness brightness) {
    final scheme = ColorScheme.fromSeed(seedColor: _seed, brightness: brightness);
    final dark = brightness == Brightness.dark;
    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      brightness: brightness,
      visualDensity: VisualDensity.compact,
      scaffoldBackgroundColor: dark ? const Color(0xFF15171C) : const Color(0xFFF6F7FB),
      cardTheme: CardThemeData(
        elevation: 0,
        margin: EdgeInsets.zero,
        color: dark ? const Color(0xFF1E2128) : Colors.white,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
          side: BorderSide(color: scheme.outlineVariant.withValues(alpha: 0.5)),
        ),
      ),
      dividerTheme: DividerThemeData(color: scheme.outlineVariant.withValues(alpha: 0.5), space: 1),
      inputDecorationTheme: InputDecorationTheme(
        isDense: true,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      ),
      tooltipTheme: const TooltipThemeData(waitDuration: Duration(milliseconds: 500)),
      navigationRailTheme: NavigationRailThemeData(
        backgroundColor: dark ? const Color(0xFF1A1C22) : const Color(0xFFEDEFF5),
        indicatorShape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
      dialogTheme: DialogThemeData(shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14))),
    );
  }
}
