import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../remote_display.dart';

/// 远程画面组件：把 [RemoteDisplay] 的帧解码为图像显示，并把键鼠事件转发给会话。
/// VNC 与 RDP 共用。[fit] 为 true 时等比缩放到窗口，否则按实际像素显示并可滚动。
class RemoteScreen extends StatefulWidget {
  const RemoteScreen({super.key, required this.display, this.fit = true});

  final RemoteDisplay display;
  final bool fit;

  @override
  State<RemoteScreen> createState() => _RemoteScreenState();
}

class _RemoteScreenState extends State<RemoteScreen> {
  ui.Image? _image;
  bool _decoding = false;
  bool _pending = false;
  int _buttons = 0;
  Size? _lastViewSize;
  final _focus = FocusNode();

  RemoteDisplay get d => widget.display;

  @override
  void initState() {
    super.initState();
    d.addListener(_onDisplay);
    _onDisplay();
  }

  @override
  void didUpdateWidget(covariant RemoteScreen old) {
    super.didUpdateWidget(old);
    if (old.display != widget.display) {
      old.display.removeListener(_onDisplay);
      widget.display.addListener(_onDisplay);
    }
  }

  @override
  void dispose() {
    d.removeListener(_onDisplay);
    _image?.dispose();
    _focus.dispose();
    super.dispose();
  }

  /// 有新帧时解码；解码期间的更新合并为一次
  void _onDisplay() {
    if (!d.displayReady) return;
    if (_decoding) {
      _pending = true;
      return;
    }
    _decode();
  }

  void _decode() {
    final pixels = d.readFrame();
    final w = d.frameWidth;
    final h = d.frameHeight;
    if (pixels == null || w <= 0 || h <= 0 || pixels.length < w * h * 4) return;
    _decoding = true;
    ui.decodeImageFromPixels(pixels, w, h, ui.PixelFormat.bgra8888, (img) {
      _decoding = false;
      if (!mounted) {
        img.dispose();
        return;
      }
      setState(() {
        _image?.dispose();
        _image = img;
      });
      if (_pending) {
        _pending = false;
        _decode();
      }
    });
  }

  /// 本地坐标转远程坐标
  Offset _toRemote(Offset local, Size box) {
    final img = _image;
    if (img == null) return Offset.zero;
    if (!widget.fit) return local;
    final scale = (box.width / img.width).clamp(0.0, box.height / img.height);
    final dx = (box.width - img.width * scale) / 2;
    final dy = (box.height - img.height * scale) / 2;
    return Offset((local.dx - dx) / scale, (local.dy - dy) / scale);
  }

  /// Flutter 按钮位掩码转为通用掩码（左 1、中 2、右 4）
  int _mask(int b) {
    var m = 0;
    if (b & kPrimaryMouseButton != 0) m |= 1;
    if (b & kMiddleMouseButton != 0) m |= 2;
    if (b & kSecondaryMouseButton != 0) m |= 4;
    return m;
  }

  void _pointer(PointerEvent e, Size box, {int? buttons}) {
    if (buttons != null) _buttons = buttons;
    final p = _toRemote(e.localPosition, box);
    d.pointerEvent(p.dx.round(), p.dy.round(), _buttons);
  }

  /// 通知会话显示区域尺寸（仅在变化时）
  void _reportSize(Size size) {
    if (_lastViewSize == size) return;
    _lastViewSize = size;
    scheduleMicrotask(() => d.viewResized(size.width.floor(), size.height.floor()));
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, box) {
        final size = Size(box.maxWidth, box.maxHeight);
        _reportSize(size);
        final img = _image;
        final Widget content = img == null
            ? const Center(child: CircularProgressIndicator())
            : widget.fit
            ? RawImage(image: img, fit: BoxFit.contain, filterQuality: FilterQuality.medium)
            : SizedBox(
                width: img.width.toDouble(),
                height: img.height.toDouble(),
                child: RawImage(image: img),
              );
        final input = Focus(
          focusNode: _focus,
          autofocus: true,
          onKeyEvent: (node, e) => d.keyEvent(e),
          onFocusChange: (f) {
            if (f) d.displayFocused();
          },
          child: MouseRegion(
            cursor: SystemMouseCursors.basic,
            child: Listener(
              onPointerDown: (e) {
                _focus.requestFocus();
                _pointer(e, size, buttons: _mask(e.buttons));
              },
              onPointerUp: (e) => _pointer(e, size, buttons: _mask(e.buttons)),
              onPointerMove: (e) => _pointer(e, size),
              onPointerHover: (e) => _pointer(e, size),
              onPointerSignal: (e) {
                if (e is PointerScrollEvent) {
                  final p = _toRemote(e.localPosition, size);
                  d.scrollEvent(p.dx.round(), p.dy.round(), e.scrollDelta.dy);
                }
              },
              child: Container(color: Colors.black, child: content),
            ),
          ),
        );
        if (widget.fit) return input;
        return SingleChildScrollView(
          child: SingleChildScrollView(scrollDirection: Axis.horizontal, child: input),
        );
      },
    );
  }
}
