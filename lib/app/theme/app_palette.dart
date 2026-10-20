import 'package:flutter/material.dart';

/// 强调色预设：同一强调色在深色 / 浅色主题下分别取值，保证对比度。
/// 新增强调色只需在 [AccentPreset.values] 中追加一项，并在多语言中添加 `accent.{id}` 文本
class AccentPreset {
  const AccentPreset({
    required this.id,
    required this.dark,
    required this.darkOn,
    required this.light,
    required this.lightFill,
    required this.lightOn,
  });

  /// 预设 id（保存在设置中）
  final String id;

  /// 深色主题：强调色（文字、图标、选中边框、主要按钮背景共用）
  final Color dark;

  /// 深色主题：主要按钮上的文字颜色
  final Color darkOn;

  /// 浅色主题：强调色（文字、图标、选中边框）
  final Color light;

  /// 浅色主题：主要按钮背景
  final Color lightFill;

  /// 浅色主题：主要按钮上的文字颜色
  final Color lightOn;

  static const sage = AccentPreset(
    id: 'sage',
    dark: Color(0xFFA7DFC3),
    darkOn: Color(0xFF0F1D16),
    light: Color(0xFF2E8A62),
    lightFill: Color(0xFF8FD3B0),
    lightOn: Color(0xFF0F1D16),
  );

  static const blue = AccentPreset(
    id: 'blue',
    dark: Color(0xFF9CC3F5),
    darkOn: Color(0xFF0E1726),
    light: Color(0xFF2F6BC4),
    lightFill: Color(0xFF9CC3F5),
    lightOn: Color(0xFF0E1726),
  );

  static const violet = AccentPreset(
    id: 'violet',
    dark: Color(0xFFC3B3F2),
    darkOn: Color(0xFF1A1430),
    light: Color(0xFF6A4FC4),
    lightFill: Color(0xFFC3B3F2),
    lightOn: Color(0xFF1A1430),
  );

  static const amber = AccentPreset(
    id: 'amber',
    dark: Color(0xFFF2C98A),
    darkOn: Color(0xFF2A1B06),
    light: Color(0xFFA8660E),
    lightFill: Color(0xFFF2C98A),
    lightOn: Color(0xFF2A1B06),
  );

  /// 全部预设（设置页按此顺序展示）
  static const values = [sage, blue, violet, amber];

  /// 按 id 查找，未知 id 回退为默认的鼠尾草绿
  static AccentPreset byId(String? id) => values.firstWhere((e) => e.id == id, orElse: () => sage);
}

/// 应用调色板：界面所有颜色的唯一来源（设计 token）。
/// 组件通过 `context.palette` 取色，不直接写死颜色值，以便切换深浅色与强调色
@immutable
class AppPalette extends ThemeExtension<AppPalette> {
  const AppPalette({
    required this.brightness,
    required this.canvas,
    required this.sidebar,
    required this.panel,
    required this.panelRaised,
    required this.hover,
    required this.input,
    required this.border,
    required this.borderStrong,
    required this.text,
    required this.textMuted,
    required this.textFaint,
    required this.accent,
    required this.accentFill,
    required this.onAccent,
    required this.accentSoft,
    required this.success,
    required this.warning,
    required this.warningSoft,
    required this.danger,
    required this.dangerSoft,
    required this.info,
    required this.protoSsh,
    required this.protoRdp,
    required this.protoVnc,
    required this.protoSftp,
    required this.folder,
  });

  final Brightness brightness;

  /// 页面画布（内容区背景）
  final Color canvas;

  /// 左侧应用导航背景
  final Color sidebar;

  /// 面板 / 卡片背景
  final Color panel;

  /// 浮层（弹窗、菜单）背景
  final Color panelRaised;

  /// 悬停背景
  final Color hover;

  /// 输入框背景
  final Color input;

  /// 常规描边
  final Color border;

  /// 较强描边（分隔线、表头）
  final Color borderStrong;

  /// 主文字
  final Color text;

  /// 次文字
  final Color textMuted;

  /// 弱文字（占位、禁用）
  final Color textFaint;

  /// 强调色（选中、链接、图标）
  final Color accent;

  /// 主要按钮背景
  final Color accentFill;

  /// 主要按钮文字
  final Color onAccent;

  /// 强调色浅底（选中行、选中分段）
  final Color accentSoft;

  /// 成功 / 已连接
  final Color success;

  /// 警告 / 待同步 / 广播
  final Color warning;

  /// 警告浅底
  final Color warningSoft;

  /// 危险 / 失败
  final Color danger;

  /// 危险浅底
  final Color dangerSoft;

  /// 信息（下载方向等）
  final Color info;

  /// 协议标签颜色
  final Color protoSsh;
  final Color protoRdp;
  final Color protoVnc;
  final Color protoSftp;

  /// 文件夹图标颜色
  final Color folder;

  bool get isDark => brightness == Brightness.dark;

  /// 深色调色板（设计稿默认）
  factory AppPalette.dark(AccentPreset a) => AppPalette(
    brightness: Brightness.dark,
    canvas: const Color(0xFF111315),
    sidebar: const Color(0xFF17191C),
    panel: const Color(0xFF1A1D20),
    panelRaised: const Color(0xFF1F2226),
    hover: const Color(0xFF23272C),
    input: const Color(0xFF15171A),
    border: const Color(0xFF2A2E34),
    borderStrong: const Color(0xFF30343B),
    text: const Color(0xFFECEDEB),
    textMuted: const Color(0xFFA0A5AD),
    textFaint: const Color(0xFF6B7078),
    accent: a.dark,
    accentFill: a.dark,
    onAccent: a.darkOn,
    accentSoft: Color.alphaBlend(a.dark.withValues(alpha: 0.12), const Color(0xFF1A1D20)),
    success: const Color(0xFF7FD6A4),
    warning: const Color(0xFFF2B35B),
    warningSoft: const Color(0xFF2B2216),
    danger: const Color(0xFFF2766B),
    dangerSoft: const Color(0xFF33201E),
    info: const Color(0xFF8DB8F2),
    protoSsh: const Color(0xFFA7DFC3),
    protoRdp: const Color(0xFF8DB8F2),
    protoVnc: const Color(0xFFC3A6F2),
    protoSftp: const Color(0xFF8DB8F2),
    folder: const Color(0xFF5AA9F0),
  );

  /// 浅色调色板
  factory AppPalette.light(AccentPreset a) => AppPalette(
    brightness: Brightness.light,
    canvas: const Color(0xFFF5F6F4),
    sidebar: const Color(0xFFECEEEB),
    panel: const Color(0xFFFFFFFF),
    panelRaised: const Color(0xFFFFFFFF),
    hover: const Color(0xFFEEF0ED),
    input: const Color(0xFFFFFFFF),
    border: const Color(0xFFDDE0DC),
    borderStrong: const Color(0xFFD0D4CF),
    text: const Color(0xFF1B1D1F),
    textMuted: const Color(0xFF5D636B),
    textFaint: const Color(0xFF9399A1),
    accent: a.light,
    accentFill: a.lightFill,
    onAccent: a.lightOn,
    accentSoft: Color.alphaBlend(a.light.withValues(alpha: 0.10), Colors.white),
    success: const Color(0xFF2E9D63),
    warning: const Color(0xFFC77A12),
    warningSoft: const Color(0xFFFFF4E3),
    danger: const Color(0xFFD9483B),
    dangerSoft: const Color(0xFFFDECEA),
    info: const Color(0xFF2F6BC4),
    protoSsh: const Color(0xFF2E8A62),
    protoRdp: const Color(0xFF2F6BC4),
    protoVnc: const Color(0xFF7A55C9),
    protoSftp: const Color(0xFF2F6BC4),
    folder: const Color(0xFF3B8FE0),
  );

  /// 按亮度与强调色构造
  factory AppPalette.of(Brightness b, AccentPreset a) =>
      b == Brightness.dark ? AppPalette.dark(a) : AppPalette.light(a);

  @override
  AppPalette copyWith() => this;

  @override
  AppPalette lerp(covariant AppPalette? other, double t) {
    if (other == null) return this;
    Color l(Color a, Color b) => Color.lerp(a, b, t)!;
    return AppPalette(
      brightness: t < 0.5 ? brightness : other.brightness,
      canvas: l(canvas, other.canvas),
      sidebar: l(sidebar, other.sidebar),
      panel: l(panel, other.panel),
      panelRaised: l(panelRaised, other.panelRaised),
      hover: l(hover, other.hover),
      input: l(input, other.input),
      border: l(border, other.border),
      borderStrong: l(borderStrong, other.borderStrong),
      text: l(text, other.text),
      textMuted: l(textMuted, other.textMuted),
      textFaint: l(textFaint, other.textFaint),
      accent: l(accent, other.accent),
      accentFill: l(accentFill, other.accentFill),
      onAccent: l(onAccent, other.onAccent),
      accentSoft: l(accentSoft, other.accentSoft),
      success: l(success, other.success),
      warning: l(warning, other.warning),
      warningSoft: l(warningSoft, other.warningSoft),
      danger: l(danger, other.danger),
      dangerSoft: l(dangerSoft, other.dangerSoft),
      info: l(info, other.info),
      protoSsh: l(protoSsh, other.protoSsh),
      protoRdp: l(protoRdp, other.protoRdp),
      protoVnc: l(protoVnc, other.protoVnc),
      protoSftp: l(protoSftp, other.protoSftp),
      folder: l(folder, other.folder),
    );
  }
}

/// BuildContext 便捷扩展：context.palette
extension PaletteContext on BuildContext {
  AppPalette get palette => Theme.of(this).extension<AppPalette>()!;
}
