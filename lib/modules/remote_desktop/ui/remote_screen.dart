import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../../../utils/app_log.dart';
import '../remote_display.dart';
import 'frame_compositor.dart';
import 'scroll_accumulator.dart';

/// 远程画面组件：把 [RemoteDisplay] 的帧合成为图像显示（只重绘变化区域），并把键鼠事件转发给会话。
/// 远程提供指针形状时在本地按鼠标位置绘制指针。
/// VNC 与 RDP 共用。[fit] 为 true 时等比缩放到窗口，否则按实际像素显示并可滚动。
class RemoteScreen extends StatefulWidget {
  const RemoteScreen({super.key, required this.display, this.fit = true});

  final RemoteDisplay display;
  final bool fit;

  @override
  State<RemoteScreen> createState() => RemoteScreenState();
}

/// 公开状态类型，供外部（如拖放上传）通过 GlobalKey 换算远程坐标
class RemoteScreenState extends State<RemoteScreen> {
  ui.Image? _image;
  bool _decoding = false;
  bool _pending = false;
  int _buttons = 0;
  Size? _lastViewSize;
  final _focus = FocusNode();
  final _scroll = ScrollAccumulator();

  /// 输入区域（画面容器），用于把全局坐标换算到画面内
  final _inputKey = GlobalKey();

  final _compositor = FrameCompositor();

  /// 本应用失去激活时释放远程按键（焦点仍在本组件时 onFocusChange 不会触发）
  AppLifecycleListener? _lifecycle;
  Timer? _statTimer;

  /// 合成期间到来、被合并的更新次数（统计用）
  int _coalesced = 0;

  /// UI 线程卡顿监测：每 [_lagProbe] 触发一次，实际间隔超出部分即 UI 线程被占用的时长
  static const _lagProbe = Duration(milliseconds: 50);
  Timer? _lagTimer;
  final _lagClock = Stopwatch();
  int _lagMax = 0;
  int _lagOver100 = 0;

  /// 本地鼠标位置（输入区域坐标），用于绘制远程指针；离开画面时为 null
  final _mouse = ValueNotifier<Offset?>(null);

  /// 远程指针图像及其来源（来源变化时重新解码）
  RemoteCursor? _cursorSrc;
  ui.Image? _cursorImage;

  RemoteDisplay get d => widget.display;

  @override
  void initState() {
    super.initState();
    d.addListener(_onDisplay);
    _onDisplay();
    _lifecycle = AppLifecycleListener(onInactive: () => widget.display.displayBlurred());
    _lagClock.start();
    _lagTimer = Timer.periodic(_lagProbe, (_) {
      final lag = _lagClock.elapsedMilliseconds - _lagProbe.inMilliseconds;
      _lagClock.reset();
      if (lag > _lagMax) _lagMax = lag;
      if (lag > 100) _lagOver100++;
    });
    // 定期把渲染统计写入日志，便于定位卡顿（与 vnc.stat 同周期，可对照）
    _statTimer = Timer.periodic(const Duration(seconds: 5), (_) {
      final c = _compositor;
      if (c.statFrames == 0) return;
      final f = c.statFrames == 0 ? 1 : c.statFrames;
      AppLog.i(
        'remote.stat',
        '5s：合成 ${c.statFrames} 次（整屏 ${c.statFull}），耗时 平均${c.statMs ~/ f}ms/最大${c.statMaxMs}ms，'
            '增量区域 ${c.statRects} 个共 ${c.statArea ~/ 1000}K 像素，合并更新 $_coalesced 次，'
            'UI 线程最长卡顿 ${_lagMax}ms（超过 100ms $_lagOver100 次）',
      );
      c.resetStats();
      _coalesced = 0;
      _lagMax = _lagOver100 = 0;
    });
  }

  @override
  void didUpdateWidget(covariant RemoteScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.display != widget.display) {
      oldWidget.display.removeListener(_onDisplay);
      widget.display.addListener(_onDisplay);
    }
  }

  @override
  void dispose() {
    d.removeListener(_onDisplay);
    _lifecycle?.dispose();
    d.displayBlurred();
    _statTimer?.cancel();
    _lagTimer?.cancel();
    _image?.dispose();
    _cursorImage?.dispose();
    _mouse.dispose();
    _focus.dispose();
    super.dispose();
  }

  /// 有新帧时合成；合成期间到来的更新合并为一次，合成完成后再处理
  void _onDisplay() {
    _syncCursor();
    if (!d.displayReady) return;
    if (_decoding) {
      if (_pending) _coalesced++;
      _pending = true;
      return;
    }
    _decode();
  }

  Future<void> _decode() async {
    _decoding = true;
    final img = await _compositor.next(d, _image);
    _decoding = false;
    if (!mounted) {
      img?.dispose();
      return;
    }
    if (img != null) {
      setState(() {
        _image?.dispose();
        _image = img;
      });
    }
    if (_pending) {
      _pending = false;
      _decode();
    }
  }

  /// 远程指针形状变化时解码为图像
  void _syncCursor() {
    final src = d.cursor;
    if (identical(src, _cursorSrc)) return;
    _cursorSrc = src;
    AppLog.d('remote', src == null ? '远程指针：使用系统指针' : '远程指针：${src.width}×${src.height} 本地绘制');
    if (src == null) {
      setState(() {
        _cursorImage?.dispose();
        _cursorImage = null;
      });
      return;
    }
    ui.decodeImageFromPixels(src.bgra, src.width, src.height, ui.PixelFormat.bgra8888, (img) {
      if (!mounted || !identical(src, _cursorSrc)) {
        img.dispose();
        return;
      }
      setState(() {
        _cursorImage?.dispose();
        _cursorImage = img;
      });
    });
  }

  /// 画面缩放比例（远程像素 → 本地逻辑像素）
  double _scale(Size box) {
    final img = _image;
    if (img == null || !widget.fit) return 1;
    return (box.width / img.width).clamp(0.0, box.height / img.height);
  }

  /// 本地绘制的远程指针：热点对齐鼠标位置，按画面缩放
  Widget _cursorOverlay(Size box) {
    final cur = _cursorImage;
    final src = _cursorSrc;
    if (cur == null || src == null) return const SizedBox.shrink();
    final s = _scale(box);
    return ValueListenableBuilder<Offset?>(
      valueListenable: _mouse,
      builder: (context, m, _) => m == null
          ? const SizedBox.shrink()
          : Positioned(
              left: m.dx - src.hotX * s,
              top: m.dy - src.hotY * s,
              child: IgnorePointer(
                child: RawImage(
                  image: cur,
                  width: src.width * s,
                  height: src.height * s,
                  fit: BoxFit.fill,
                  filterQuality: FilterQuality.medium,
                ),
              ),
            ),
    );
  }

  /// 全局坐标转远程画面像素坐标；不在画面内或尚无画面返回 null
  Offset? remoteFromGlobal(Offset global) {
    final box = _inputKey.currentContext?.findRenderObject() as RenderBox?;
    final img = _image;
    if (box == null || !box.hasSize || img == null) return null;
    final p = _toRemote(box.globalToLocal(global), box.size);
    if (p.dx < 0 || p.dy < 0 || p.dx >= img.width || p.dy >= img.height) return null;
    return p;
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
    _mouse.value = e.localPosition;
    final p = _toRemote(e.localPosition, box);
    d.pointerEvent(p.dx.round(), p.dy.round(), _buttons);
  }

  /// 通知会话显示区域尺寸（仅在变化时）
  void _reportSize(Size size) {
    if (_lastViewSize == size) return;
    _lastViewSize = size;
    scheduleMicrotask(() => d.viewResized(size.width.floor(), size.height.floor()));
  }

  /// 在远程坐标处发送 [steps] 格滚轮
  void _sendScroll(Offset local, Size size, int steps) {
    if (steps == 0) return;
    final p = _toRemote(local, size);
    d.scrollEvent(p.dx.round(), p.dy.round(), steps);
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
            if (f) {
              d.displayFocused();
            } else {
              d.displayBlurred();
            }
          },
          child: MouseRegion(
            // 远程提供指针形状时隐藏系统指针，由本地绘制远程指针
            cursor: _cursorImage != null ? SystemMouseCursors.none : SystemMouseCursors.basic,
            onExit: (_) => _mouse.value = null,
            child: Listener(
              onPointerDown: (e) {
                _focus.requestFocus();
                _pointer(e, size, buttons: _mask(e.buttons));
              },
              onPointerUp: (e) => _pointer(e, size, buttons: _mask(e.buttons)),
              onPointerMove: (e) => _pointer(e, size),
              onPointerHover: (e) => _pointer(e, size),
              // 鼠标滚轮：按位移折算格数，每个事件至少一格
              onPointerSignal: (e) {
                if (e is PointerScrollEvent) {
                  _sendScroll(e.localPosition, size, _scroll.addWheel(e.scrollDelta.dy));
                }
              },
              // macOS 等平台的触控板双指滚动以平移手势上报：手指下移对应向上滚动
              onPointerPanZoomStart: (_) => _scroll.reset(),
              onPointerPanZoomUpdate: (e) => _sendScroll(e.localPosition, size, _scroll.add(-e.localPanDelta.dy)),
              onPointerPanZoomEnd: (_) => _scroll.reset(),
              child: Container(
                key: _inputKey,
                color: Colors.black,
                child: Stack(
                  fit: StackFit.passthrough,
                  children: [content, _cursorOverlay(widget.fit ? size : Size.zero)],
                ),
              ),
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
