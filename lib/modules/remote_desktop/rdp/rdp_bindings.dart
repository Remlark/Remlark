// ignore_for_file: non_constant_identifier_names

// RDP 胶水库（native/rdp）的 FFI 绑定。库由 hook/build.dart 作为代码资源打包，
// 通过 @DefaultAsset 自动解析，无需按平台拼接路径。
@DefaultAsset('package:remlark/rdp')
library;

import 'dart:ffi';

import 'package:ffi/ffi.dart';

/// 事件回调签名：(会话 id, 事件类型, a, b, c, d, 字符串)
typedef RmkEventCallbackNative = Void Function(Int64, Int32, Int32, Int32, Int32, Int32, Pointer<Utf8>);

/// 不透明的会话句柄
final class RmkRdp extends Opaque {}

@Native<Pointer<RmkRdp> Function(Int64, Pointer<NativeFunction<RmkEventCallbackNative>>)>()
external Pointer<RmkRdp> rmk_rdp_new(int id, Pointer<NativeFunction<RmkEventCallbackNative>> callback);

@Native<
  Int32 Function(
    Pointer<RmkRdp>,
    Pointer<Utf8>,
    Int32,
    Pointer<Utf8>,
    Pointer<Utf8>,
    Pointer<Utf8>,
    Int32,
    Int32,
    Pointer<Utf8>,
    Int32,
    Pointer<Utf8>,
    Pointer<Utf8>,
  )
>()
external int rmk_rdp_connect(
  Pointer<RmkRdp> rdp,
  Pointer<Utf8> host,
  int port,
  Pointer<Utf8> username,
  Pointer<Utf8> password,
  Pointer<Utf8> domain,
  int width,
  int height,
  Pointer<Utf8> sharedDir,
  int clipboard,
  Pointer<Utf8> knownFingerprint,
  Pointer<Utf8> tempDir,
);

@Native<Void Function(Pointer<RmkRdp>, Int32, Pointer<Utf8>, Int32, Pointer<Utf8>, Pointer<Utf8>)>()
external void rmk_rdp_set_proxy(
  Pointer<RmkRdp> rdp,
  int type,
  Pointer<Utf8> host,
  int port,
  Pointer<Utf8> username,
  Pointer<Utf8> password,
);

/// 是否在本机播放远程声音（connect 之前调用）
@Native<Void Function(Pointer<RmkRdp>, Int32)>()
external void rmk_rdp_set_audio(Pointer<RmkRdp> rdp, int enabled);

/// 是否允许 H.264 硬件解码（connect 之前调用）
@Native<Void Function(Pointer<RmkRdp>, Int32)>()
external void rmk_rdp_set_hwdec(Pointer<RmkRdp> rdp, int enabled);

@Native<Void Function(Pointer<RmkRdp>)>()
external void rmk_rdp_disconnect(Pointer<RmkRdp> rdp);

@Native<Void Function(Pointer<RmkRdp>)>()
external void rmk_rdp_free(Pointer<RmkRdp> rdp);

/// 一次最多返回的变化区域块数（与 RMK_RDP_MAX_RECTS 一致）
const rmkRdpMaxRects = 16;

/// 取出变化区域；leaf 调用，dst 可直接传 Uint8List（无额外拷贝）
@Native<
  Int32 Function(
    Pointer<RmkRdp>,
    Pointer<Uint8>,
    Int32,
    Pointer<Int32>,
    Pointer<Int32>,
    Pointer<Int32>,
    Pointer<Int32>,
    Pointer<Int32>,
  )
>(isLeaf: true)
external int rmk_rdp_take_frame(
  Pointer<RmkRdp> rdp,
  Pointer<Uint8> dst,
  int dstSize,
  Pointer<Int32> width,
  Pointer<Int32> height,
  Pointer<Int32> rects,
  Pointer<Int32> nrects,
  Pointer<Int32> full,
);

@Native<Void Function(Pointer<RmkRdp>, Int32, Int32, Int32)>()
external void rmk_rdp_send_key(Pointer<RmkRdp> rdp, int scancode, int down, int repeat);

@Native<Void Function(Pointer<RmkRdp>, Int32, Int32)>()
external void rmk_rdp_send_unicode(Pointer<RmkRdp> rdp, int codepoint, int down);

@Native<Void Function(Pointer<RmkRdp>, Int32, Int32, Int32)>()
external void rmk_rdp_send_mouse(Pointer<RmkRdp> rdp, int flags, int x, int y);

@Native<Void Function(Pointer<RmkRdp>, Int32, Int32)>()
external void rmk_rdp_resize(Pointer<RmkRdp> rdp, int width, int height);

@Native<Void Function(Pointer<RmkRdp>, Pointer<Utf8>)>()
external void rmk_rdp_set_clipboard_text(Pointer<RmkRdp> rdp, Pointer<Utf8> text);

@Native<Void Function(Pointer<RmkRdp>, Pointer<Utf8>)>()
external void rmk_rdp_set_clipboard_files(Pointer<RmkRdp> rdp, Pointer<Utf8> paths);

@Native<Void Function(Pointer<Utf8>)>()
external void rmk_rdp_free_string(Pointer<Utf8> str);

@Native<Pointer<Utf8> Function()>()
external Pointer<Utf8> rmk_rdp_version();

/// H.264 解码能力位：已编入解码器（与 RMK_H264_DECODER 一致）
const rmkH264Decoder = 1;

/// H.264 解码能力位：平台硬件解码可用，已实际解码校验（与 RMK_H264_HARDWARE 一致）
const rmkH264Hardware = 2;

/// 探测 H.264 解码能力（首次调用会创建硬件设备并实际解码一帧内置画面，结果由原生库缓存）
@Native<Int32 Function()>()
external int rmk_rdp_h264_caps();

/// 自检：把一帧 H.264 解码为 BGRA（多平台测试用），返回值 >= 0 表示成功
@Native<Int32 Function(Pointer<Uint8>, Int32, Int32, Int32, Int32, Pointer<Uint8>)>()
external int rmk_rdp_h264_self_test(
  Pointer<Uint8> data,
  int size,
  int width,
  int height,
  int hardware,
  Pointer<Uint8> bgra,
);

/// 用实际视频流检查硬件解码（与连接中表面首个 H.264 命令的处理相同）：
/// 1 硬件可解码（或本就软件解码），0 硬件失败但软件成功（会话改用软件解码），-1 都失败
@Native<Int32 Function(Pointer<Uint8>, Int32, Int32, Int32)>()
external int rmk_rdp_h264_stream_check(Pointer<Uint8> data, int size, int width, int height);

/// 当前平台使用的硬件解码设备类型：videotoolbox / d3d11va / vaapi
@Native<Pointer<Utf8> Function()>()
external Pointer<Utf8> rmk_rdp_h264_hw_type();
