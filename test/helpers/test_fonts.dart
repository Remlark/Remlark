import 'dart:io';

import 'package:flutter/services.dart';

/// 加载真实字体（含中文）与 Material 图标字体，使测试中的文字宽度接近真实界面。
/// 找不到字体时保持测试默认字体（Ahem，字形更宽，更容易暴露溢出）。
Future<void> loadTestFonts() async {
  const candidates = [
    '/System/Library/Fonts/Supplemental/Arial Unicode.ttf',
    '/usr/share/fonts/opentype/noto/NotoSansCJK-Regular.ttc',
    '/usr/share/fonts/truetype/noto/NotoSansCJK-Regular.ttc',
    r'C:\Windows\Fonts\msyh.ttc',
  ];
  final font = candidates.map(File.new).where((f) => f.existsSync()).firstOrNull;
  if (font != null) {
    final bytes = ByteData.sublistView(font.readAsBytesSync());
    for (final family in ['Roboto', '.SF UI Text', '.SF UI Display', '.AppleSystemUIFont', 'monospace', 'Menlo']) {
      await (FontLoader(family)..addFont(Future.value(bytes))).load();
    }
  }
  final root = Platform.environment['FLUTTER_ROOT'];
  final icons = File('$root/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf');
  if (root != null && icons.existsSync()) {
    await (FontLoader('MaterialIcons')..addFont(Future.value(ByteData.sublistView(icons.readAsBytesSync())))).load();
  }
}
