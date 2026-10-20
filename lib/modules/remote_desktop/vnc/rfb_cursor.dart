import 'dart:typed_data';

import '../remote_display.dart';

/// RFB Cursor 伪编码（-239）解码。客户端声明支持后，服务器不再把指针画进帧缓冲，
/// 指针由本地按鼠标位置绘制，移动无延迟，也避免每次移动鼠标都触发一次画面更新
class RfbCursor {
  RfbCursor._();

  /// [pixels] 为 w*h 个 32 位像素（与协商的像素格式一致，内存顺序 BGRX），
  /// [mask] 为每行 ⌈w/8⌉ 字节的位掩码（1 表示不透明）；w 或 h 为 0 表示隐藏指针
  static RemoteCursor? decode(int w, int h, int hotX, int hotY, Uint8List pixels, Uint8List mask) {
    if (w <= 0 || h <= 0) return null;
    final out = Uint8List(w * h * 4);
    final rowBytes = (w + 7) ~/ 8;
    for (var y = 0; y < h; y++) {
      for (var x = 0; x < w; x++) {
        final i = (y * w + x) * 4;
        final visible = (mask[y * rowBytes + (x >> 3)] >> (7 - (x & 7))) & 1 == 1;
        out[i] = pixels[i];
        out[i + 1] = pixels[i + 1];
        out[i + 2] = pixels[i + 2];
        out[i + 3] = visible ? 255 : 0;
      }
    }
    return RemoteCursor(width: w, height: h, hotX: hotX, hotY: hotY, bgra: out);
  }
}
