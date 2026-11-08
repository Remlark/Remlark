import 'dart:io';

import 'package:flutter/services.dart';

/// 加载真实字体（含中文）与 Material 图标字体，使测试中的文字宽度接近真实界面。
/// 找不到字体时保持测试默认字体（Ahem，字形更宽，更容易暴露溢出）。
/// [realMonospace] 为 true 时 macOS 终端使用的 Menlo 字体族改用系统等宽字体（用于展示截图）；
/// 界面中其他 monospace 文字可能含中文，仍用中文字体。默认关闭，保持各布局测试的字宽基准不变。
Future<void> loadTestFonts({bool realMonospace = false}) async {
  const candidates = [
    '/System/Library/Fonts/Supplemental/Arial Unicode.ttf',
    '/usr/share/fonts/opentype/noto/NotoSansCJK-Regular.ttc',
    '/usr/share/fonts/truetype/noto/NotoSansCJK-Regular.ttc',
    r'C:\Windows\Fonts\msyh.ttc',
  ];
  const monoCandidates = [
    '/System/Library/Fonts/SFNSMono.ttf',
    '/usr/share/fonts/truetype/dejavu/DejaVuSansMono.ttf',
    r'C:\Windows\Fonts\consola.ttf',
  ];
  ByteData? read(List<String> paths) {
    final f = paths.map(File.new).where((f) => f.existsSync()).firstOrNull;
    return f == null ? null : ByteData.sublistView(f.readAsBytesSync());
  }

  final font = read(candidates);
  final mono = realMonospace ? read(monoCandidates) : null;
  if (font != null) {
    for (final family in ['Roboto', '.SF UI Text', '.SF UI Display', '.AppleSystemUIFont', 'monospace', 'Menlo']) {
      // 同一字体族加载多个字体时等宽字体不会生效，因此 Menlo 只加载等宽字体
      final isMono = mono != null && family == 'Menlo';
      await (FontLoader(family)..addFont(Future.value(isMono ? mono : font))).load();
    }
  }
  final root = Platform.environment['FLUTTER_ROOT'];
  final icons = File('$root/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf');
  if (root != null && icons.existsSync()) {
    await (FontLoader('MaterialIcons')..addFont(Future.value(ByteData.sublistView(icons.readAsBytesSync())))).load();
  }
}
