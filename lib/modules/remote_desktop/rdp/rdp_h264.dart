import 'dart:ffi';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';

import 'rdp_bindings.dart';

/// RDP H.264（AVC420 / AVC444）解码能力：原生库经 FFmpeg 使用平台硬件解码，
/// 设备由 native/rdp/src/hwdec/ 下的平台实现选择（macOS VideoToolbox / Windows D3D11VA / Linux VAAPI）
class RdpH264Support {
  const RdpH264Support({required this.decoder, required this.hardware, required this.hwType});

  /// 是否编入了 H.264 解码器（为 false 时连接不协商 H.264，使用 RemoteFX 等编码）
  final bool decoder;

  /// 平台硬件解码是否可用：设备可创建且实际解码一帧成功（不可用时 FFmpeg 软件解码）
  final bool hardware;

  /// 平台硬件解码设备类型
  final String hwType;

  /// 原生库不支持 H.264（旧版本库缺少接口）时的结果
  static const unsupported = RdpH264Support(decoder: false, hardware: false, hwType: '');

  static RdpH264Support? _cached;

  /// 探测当前机器的解码能力（只探测一次）
  static RdpH264Support probe() {
    return _cached ??= _probe();
  }

  /// 调用原生接口；缺少接口时视为不支持
  static RdpH264Support _probe() {
    try {
      final caps = rmk_rdp_h264_caps();
      return RdpH264Support(
        decoder: caps & rmkH264Decoder != 0,
        hardware: caps & rmkH264Hardware != 0,
        hwType: rmk_rdp_h264_hw_type().toDartString(),
      );
    } on ArgumentError {
      return unsupported;
    }
  }

  /// 自检：用与连接相同的 FreeRDP 解码流程把一帧 H.264（Annex B）解码为 BGRA；
  /// [hardware] 为 true 时使用平台硬件解码（不可用时原生库自动软件解码）。失败返回 null
  static Uint8List? selfTest(Uint8List h264, int width, int height, {required bool hardware}) {
    final src = malloc<Uint8>(h264.length);
    final dst = malloc<Uint8>(width * height * 4);
    try {
      src.asTypedList(h264.length).setAll(0, h264);
      final rc = rmk_rdp_h264_self_test(src, h264.length, width, height, hardware ? 1 : 0, dst);
      return rc < 0 ? null : Uint8List.fromList(dst.asTypedList(width * height * 4));
    } finally {
      malloc.free(src);
      malloc.free(dst);
    }
  }

  /// 用实际视频流（Annex B，含 SPS / IDR）检查硬件解码，与连接中的回退判断相同：
  /// 1 硬件可解码（或本就软件解码），0 硬件失败但软件成功，-1 都失败
  static int streamCheck(Uint8List h264, int width, int height) {
    final src = malloc<Uint8>(h264.length);
    try {
      src.asTypedList(h264.length).setAll(0, h264);
      return rmk_rdp_h264_stream_check(src, h264.length, width, height);
    } finally {
      malloc.free(src);
    }
  }

  /// 平台硬件解码设备的显示名
  String get hwName => switch (hwType) {
    'videotoolbox' => 'VideoToolbox',
    'd3d11va' => 'Direct3D 11 (D3D11VA)',
    'vaapi' => 'VA-API',
    _ => hwType,
  };

  /// 日志描述；[hardwareDecode] 为设置中是否允许硬件解码
  String describe({bool hardwareDecode = true}) {
    if (!decoder) return '未启用 H.264';
    if (!hardwareDecode) return 'H.264 软件解码（设置中已关闭硬件解码）';
    return hardware ? 'H.264 硬件解码（$hwType）' : 'H.264 软件解码（$hwType 不可用）';
  }
}
