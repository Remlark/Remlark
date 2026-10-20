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
