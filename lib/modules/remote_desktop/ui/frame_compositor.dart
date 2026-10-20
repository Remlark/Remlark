import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/painting.dart';

import '../remote_display.dart';

/// 远程画面合成（多线程渲染流水线的 UI 侧）：取出完整的画面更新，
/// 把各变化区域交给引擎解码（引擎 IO 线程），再在 GPU 上一次性覆盖到上一帧生成新图像（光栅线程）。
/// 协议解析与像素解码在后台 isolate 完成（见 RfbIsolateClient），UI 线程只做调度。
/// 每次更新整体替换，不会出现新旧画面混合（撕裂）
class FrameCompositor {
  /// 基于上一帧 [previous] 生成新图像；没有新内容返回 null。
  /// 返回的新图像由调用方持有，[previous] 仍由调用方负责释放
  Future<ui.Image?> next(RemoteDisplay d, ui.Image? previous) async {
    final u = d.takeFrame();
    if (u == null || u.width <= 0 || u.height <= 0) return null;
    final w = u.width, h = u.height;
    final sizeChanged = previous == null || previous.width != w || previous.height != h;

    final ui.Image result;
    if (u.full && u.patches.length == 1) {
      final p = u.patches.single;
      if (p.bgra.length < w * h * 4) return null;
      result = await _decode(p.bgra, w, h);
    } else {
      final images = await Future.wait([for (final p in u.patches) _decode(p.bgra, p.w, p.h)]);
      final recorder = ui.PictureRecorder();
      final canvas = Canvas(recorder);
      // src 混合：直接覆盖像素；尺寸变化或没有上一帧时以黑色为底
      final paint = Paint()..blendMode = BlendMode.src;
      if (!sizeChanged) {
        canvas.drawImage(previous, Offset.zero, paint);
      } else {
        canvas.drawRect(Rect.fromLTWH(0, 0, w.toDouble(), h.toDouble()), Paint()..color = const Color(0xFF000000));
      }
      for (var i = 0; i < images.length; i++) {
        final p = u.patches[i];
        canvas.drawImage(images[i], Offset(p.x.toDouble(), p.y.toDouble()), paint);
      }
      final picture = recorder.endRecording();
      result = picture.toImageSync(w, h);
      picture.dispose();
      for (final img in images) {
        img.dispose();
      }
    }
    return result;
  }

  static Future<ui.Image> _decode(Uint8List pixels, int w, int h) {
    final c = Completer<ui.Image>();
    ui.decodeImageFromPixels(pixels, w, h, ui.PixelFormat.bgra8888, c.complete);
    return c.future;
  }
}
