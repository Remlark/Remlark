import 'package:flutter/material.dart';

import 'app_palette.dart';

/// 统一尺寸规范（8px 间距基准）
class AppSizes {
  AppSizes._();

  /// 左侧应用导航宽度
  static const sidebarWidth = 196.0;

  /// 常规控件（按钮、输入框）高度
  static const control = 40.0;

  /// 紧凑控件（会话工具栏）高度
  static const controlCompact = 32.0;

  /// 控件圆角
  static const radius = 8.0;

  /// 面板 / 弹窗圆角
  static const radiusLarge = 12.0;

  /// 页面左右内边距
  static const pagePadding = 28.0;

  /// 二级导航（分组、设置分区）宽度
  static const subNavWidth = 232.0;
}

/// 应用主题：由 [AppPalette] 生成 Material 3 主题与各组件样式
class AppTheme {
  AppTheme._();

  /// 构造主题
  static ThemeData build(Brightness brightness, AccentPreset accent) {
    final p = AppPalette.of(brightness, accent);
    final scheme = ColorScheme(
      brightness: brightness,
      primary: p.accent,
      onPrimary: p.onAccent,
      primaryContainer: p.accentSoft,
      onPrimaryContainer: p.accent,
      secondary: p.accent,
      onSecondary: p.onAccent,
      secondaryContainer: p.accentSoft,
      onSecondaryContainer: p.text,
      tertiary: p.info,
      onTertiary: p.onAccent,
      error: p.danger,
      onError: Colors.white,
      errorContainer: p.dangerSoft,
      onErrorContainer: p.danger,
      surface: p.panel,
      onSurface: p.text,
      onSurfaceVariant: p.textMuted,
      surfaceContainerLowest: p.canvas,
      surfaceContainerLow: p.sidebar,
      surfaceContainer: p.panel,
      surfaceContainerHigh: p.panelRaised,
      surfaceContainerHighest: p.hover,
      outline: p.textFaint,
      outlineVariant: p.border,
      shadow: Colors.black,
      inverseSurface: p.text,
      onInverseSurface: p.canvas,
      inversePrimary: p.accent,
    );
    // 基础文字样式取自默认主题，保证自定义样式保留平台字体族
    final base = ThemeData(useMaterial3: true, brightness: brightness, colorScheme: scheme).textTheme;
    TextStyle ts(double size, [FontWeight weight = FontWeight.w500, Color? color]) =>
        base.labelLarge!.copyWith(fontSize: size, fontWeight: weight, color: color, letterSpacing: 0);
    final radius = BorderRadius.circular(AppSizes.radius);
    final radiusLarge = BorderRadius.circular(AppSizes.radiusLarge);
    final borderSide = BorderSide(color: p.borderStrong);
    const buttonSize = Size(64, AppSizes.control);
    const buttonPadding = EdgeInsets.symmetric(horizontal: 16);

    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: scheme,
      extensions: [p],
      visualDensity: VisualDensity.standard,
      scaffoldBackgroundColor: p.canvas,
      canvasColor: p.canvas,
      dividerColor: p.border,
      hoverColor: p.hover,
      splashFactory: NoSplash.splashFactory,
      dividerTheme: DividerThemeData(color: p.border, space: 1, thickness: 1),
      iconTheme: IconThemeData(color: p.textMuted, size: 18),
      cardTheme: CardThemeData(
        elevation: 0,
        margin: EdgeInsets.zero,
        color: p.panel,
        shape: RoundedRectangleBorder(
          borderRadius: radiusLarge,
          side: BorderSide(color: p.border),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: p.accentFill,
          foregroundColor: p.onAccent,
          disabledBackgroundColor: p.hover,
          disabledForegroundColor: p.textFaint,
          minimumSize: buttonSize,
          padding: buttonPadding,
          shape: RoundedRectangleBorder(borderRadius: radius),
          textStyle: ts(14, FontWeight.w600),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: p.text,
          backgroundColor: p.panel,
          disabledForegroundColor: p.textFaint,
          minimumSize: buttonSize,
          padding: buttonPadding,
          side: borderSide,
          shape: RoundedRectangleBorder(borderRadius: radius),
          textStyle: ts(14),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: p.accent,
          minimumSize: const Size(48, 36),
          shape: RoundedRectangleBorder(borderRadius: radius),
          textStyle: ts(14),
        ),
      ),
      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(
          foregroundColor: p.textMuted,
          iconSize: 18,
          shape: RoundedRectangleBorder(borderRadius: radius),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        isDense: true,
        filled: true,
        fillColor: p.input,
        hoverColor: Colors.transparent,
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        hintStyle: TextStyle(color: p.textFaint, fontSize: 14),
        labelStyle: TextStyle(color: p.textMuted, fontSize: 14),
        floatingLabelStyle: TextStyle(color: p.accent),
        helperStyle: TextStyle(color: p.textFaint, fontSize: 12),
        prefixIconColor: p.textFaint,
        suffixIconColor: p.textFaint,
        border: OutlineInputBorder(borderRadius: radius, borderSide: borderSide),
        enabledBorder: OutlineInputBorder(borderRadius: radius, borderSide: borderSide),
        focusedBorder: OutlineInputBorder(
          borderRadius: radius,
          borderSide: BorderSide(color: p.accent, width: 1.4),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: radius,
          borderSide: BorderSide(color: p.danger),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: radius,
          borderSide: BorderSide(color: p.danger, width: 1.4),
        ),
        disabledBorder: OutlineInputBorder(
          borderRadius: radius,
          borderSide: BorderSide(color: p.border),
        ),
      ),
      segmentedButtonTheme: SegmentedButtonThemeData(
        style: ButtonStyle(
          minimumSize: const WidgetStatePropertyAll(Size(0, AppSizes.control)),
          side: WidgetStateProperty.resolveWith(
            (s) => BorderSide(color: s.contains(WidgetState.selected) ? p.accent : p.borderStrong),
          ),
          backgroundColor: WidgetStateProperty.resolveWith(
            (s) => s.contains(WidgetState.selected) ? p.accentSoft : p.input,
          ),
          foregroundColor: WidgetStateProperty.resolveWith(
            (s) => s.contains(WidgetState.disabled)
                ? p.textFaint
                : s.contains(WidgetState.selected)
                ? p.accent
                : p.textMuted,
          ),
          shape: WidgetStatePropertyAll(RoundedRectangleBorder(borderRadius: radius)),
          textStyle: WidgetStatePropertyAll(ts(14)),
        ),
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? p.onAccent : p.textMuted),
        trackColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? p.accentFill : p.input),
        trackOutlineColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.selected) ? p.accentFill : p.borderStrong,
        ),
      ),
      checkboxTheme: CheckboxThemeData(
        fillColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? p.accentFill : null),
        checkColor: WidgetStatePropertyAll(p.onAccent),
        side: BorderSide(color: p.textFaint, width: 1.4),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
      ),
      radioTheme: RadioThemeData(
        fillColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? p.accent : p.textFaint),
      ),
      sliderTheme: SliderThemeData(
        activeTrackColor: p.accentFill,
        inactiveTrackColor: p.borderStrong,
        thumbColor: p.accentFill,
        overlayColor: p.accent.withValues(alpha: 0.12),
        trackHeight: 4,
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: p.accent,
        linearTrackColor: p.borderStrong,
        circularTrackColor: Colors.transparent,
      ),
      tabBarTheme: TabBarThemeData(
        labelColor: p.accent,
        unselectedLabelColor: p.textMuted,
        indicatorColor: p.accent,
        indicatorSize: TabBarIndicatorSize.label,
        dividerColor: Colors.transparent,
        labelStyle: ts(15, FontWeight.w600),
        unselectedLabelStyle: ts(15),
        overlayColor: const WidgetStatePropertyAll(Colors.transparent),
      ),
      listTileTheme: ListTileThemeData(
        iconColor: p.textMuted,
        textColor: p.text,
        selectedColor: p.accent,
        selectedTileColor: p.accentSoft,
        shape: RoundedRectangleBorder(borderRadius: radius),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: p.panelRaised,
        surfaceTintColor: Colors.transparent,
        elevation: 12,
        shape: RoundedRectangleBorder(
          borderRadius: radiusLarge,
          side: BorderSide(color: p.borderStrong),
        ),
        titleTextStyle: ts(18, FontWeight.w700, p.text),
        contentTextStyle: ts(14, FontWeight.w400, p.textMuted).copyWith(height: 1.5),
      ),
      popupMenuTheme: PopupMenuThemeData(
        color: p.panelRaised,
        surfaceTintColor: Colors.transparent,
        elevation: 8,
        shape: RoundedRectangleBorder(
          borderRadius: radius,
          side: BorderSide(color: p.borderStrong),
        ),
        textStyle: ts(14, FontWeight.w400, p.text),
      ),
      menuTheme: MenuThemeData(
        style: MenuStyle(
          backgroundColor: WidgetStatePropertyAll(p.panelRaised),
          surfaceTintColor: const WidgetStatePropertyAll(Colors.transparent),
          elevation: const WidgetStatePropertyAll(8),
          side: WidgetStatePropertyAll(BorderSide(color: p.borderStrong)),
          shape: WidgetStatePropertyAll(RoundedRectangleBorder(borderRadius: radius)),
          padding: const WidgetStatePropertyAll(EdgeInsets.symmetric(vertical: 6)),
        ),
      ),
      menuButtonTheme: MenuButtonThemeData(
        style: ButtonStyle(
          foregroundColor: WidgetStatePropertyAll(p.text),
          iconColor: WidgetStatePropertyAll(p.textMuted),
          minimumSize: const WidgetStatePropertyAll(Size(180, 38)),
          padding: const WidgetStatePropertyAll(EdgeInsets.symmetric(horizontal: 14)),
          backgroundColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.hovered) ? p.hover : null),
        ),
      ),
      dropdownMenuTheme: DropdownMenuThemeData(
        menuStyle: MenuStyle(
          backgroundColor: WidgetStatePropertyAll(p.panelRaised),
          surfaceTintColor: const WidgetStatePropertyAll(Colors.transparent),
        ),
      ),
      tooltipTheme: TooltipThemeData(
        waitDuration: const Duration(milliseconds: 500),
        decoration: BoxDecoration(
          color: p.panelRaised,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: p.borderStrong),
        ),
        textStyle: ts(12, FontWeight.w400, p.text),
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: p.panelRaised,
        contentTextStyle: ts(14, FontWeight.w400, p.text),
        actionTextColor: p.accent,
        shape: RoundedRectangleBorder(
          borderRadius: radius,
          side: BorderSide(color: p.borderStrong),
        ),
      ),
      scrollbarTheme: ScrollbarThemeData(
        thumbColor: WidgetStatePropertyAll(p.borderStrong),
        radius: const Radius.circular(4),
        thickness: const WidgetStatePropertyAll(6),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: p.panel,
        side: BorderSide(color: p.borderStrong),
        labelStyle: ts(13, FontWeight.w400, p.text),
        shape: RoundedRectangleBorder(borderRadius: radius),
      ),
      badgeTheme: BadgeThemeData(backgroundColor: p.accentFill, textColor: p.onAccent),
    );
  }
}
