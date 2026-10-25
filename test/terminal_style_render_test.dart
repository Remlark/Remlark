import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:remlark/modules/terminal/reflow_safe_terminal.dart';
import 'package:remlark/modules/terminal/ui/terminal_themes.dart';
// 直接检查依赖的实际绘制器，覆盖终端字符段落缓存。
import 'package:xterm/src/ui/painter.dart';
import 'package:xterm/xterm.dart';

/// 将缓冲区字符经真实终端绘制器栅格化，用像素比较检查缓存中的格式污染。
Future<Uint8List> _render(TerminalPainter painter, CellData cell) async {
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  painter.paintCell(canvas, const Offset(4, 4), cell);
  final picture = recorder.endRecording();
  final image = await picture.toImage(48, 48);
  try {
    final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
    return Uint8List.fromList(data!.buffer.asUint8List());
  } finally {
    image.dispose();
    picture.dispose();
  }
}

/// 检查浅色和深色主题下，样式切换后相同字符不复用错误的彩色段落。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  for (final brightness in Brightness.values) {
    test('绘制缓存 ${brightness.name} 重置后与全新普通文字像素一致', () async {
      final theme = TerminalThemesX.byId('auto', brightness);
      final painter = TerminalPainter(
        theme: theme,
        textStyle: const TerminalStyle(fontSize: 20),
        textScaler: TextScaler.noScaling,
      );
      final freshPainter = TerminalPainter(
        theme: theme,
        textStyle: const TerminalStyle(fontSize: 20),
        textScaler: TextScaler.noScaling,
      );
      final plain = ReflowSafeTerminal()..write('M');
      final plainCell = CellData.empty();
      plain.buffer.lines[0].getCellData(0, plainCell);
      final expected = await _render(freshPainter, plainCell);
      try {
        for (final style in [
          '1;35',
          '2;31',
          '3;32',
          '4;34',
          '7;31;44',
          '38;5;200;48;5;120',
          '1;3;4;38;2;200;30;120;48;2;12;34;56',
        ]) {
          final terminal = ReflowSafeTerminal()
            ..write('\x1b[${style}mM\x1b[0mM');
          final styled = CellData.empty();
          final reset = CellData.empty();
          terminal.buffer.lines[0].getCellData(0, styled);
          terminal.buffer.lines[0].getCellData(1, reset);
          // 先绘制带格式字符以填入缓存，再绘制相同的已重置字符。
          expect(
            await _render(painter, styled),
            isNot(orderedEquals(expected)),
            reason: '带格式字符必须确实与普通字符不同：$style',
          );
          expect(
            await _render(painter, reset),
            orderedEquals(expected),
            reason: '重置后不能沿用缓存中的格式：$style',
          );
        }
      } finally {
        painter.clearFontCache();
        freshPainter.clearFontCache();
      }
    });
  }
}
