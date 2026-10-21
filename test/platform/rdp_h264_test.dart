import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:remlark/modules/remote_desktop/rdp/rdp_client.dart';
import 'package:remlark/modules/remote_desktop/rdp/rdp_h264.dart';

/// 多平台测试 P-11：RDP H.264 硬件解码（见 docs/multi-platform-testing.md）
/// 各平台的硬件解码实现在 native/rdp/src/hwdec/rmk_hwdec_<平台>.c，FFmpeg 硬件加速在构建脚本中按平台开启。
/// 已编译原生库时实际解码 fixtures/h264_320x240.h264（libx264 编码，左半 #E04020、右半 #3080C0），
/// 软件与硬件解码都要得到正确颜色且两者一致；未编译原生库时只做静态检查。
void main() {
  String src(String path) => File(path).readAsStringSync();

  // CI 构建后必须实际加载原生库，禁止因库缺失而跳过所有解码测试。
  setUpAll(() {
    if (Platform.environment['RMK_REQUIRE_RDP_NATIVE'] == '1') {
      expect(RdpClient.isAvailable, isTrue, reason: '构建后的 RDP 原生库必须可加载');
    }
  });

  /// 各平台的硬件解码实现文件与设备类型
  const platforms = {
    'macos': 'videotoolbox',
    'windows': 'd3d11va',
    'linux': 'vaapi',
  };

  test('三个平台都有硬件解码实现，CMake 按平台选择', () {
    final cmake = src('native/rdp/CMakeLists.txt');
    for (final MapEntry(key: os, value: type) in platforms.entries) {
      final file = 'native/rdp/src/hwdec/rmk_hwdec_$os.c';
      expect(cmake, contains('src/hwdec/rmk_hwdec_$os.c'), reason: os);
      final code = src(file);
      // 实现接口中的三个函数，设备类型与平台一致
      for (final fn in ['rmk_hwdec_type', 'rmk_hwdec_device', 'rmk_hwdec_prepare']) {
        expect(code, contains('$fn(void)'), reason: '$file 缺少 $fn');
      }
      expect(code, contains('return "$type";'), reason: file);
      expect(code, contains('FREERDP_HWCTX_TYPE'), reason: file);
    }
    // Linux 自动选择可用的渲染节点
    expect(src('native/rdp/src/hwdec/rmk_hwdec_linux.c'), contains('FREERDP_HWCTX_DEVICE'));
  });

  test('构建脚本：FFmpeg 只编译 H.264 解码器并按平台开启硬件加速，FreeRDP 使用 FFmpeg 硬件解码', () {
    final sh = src('native/rdp/scripts/build.sh');
    final ps = src('native/rdp/scripts/build.ps1');
    // Windows 的 FFmpeg 由 build.ps1 通过 MSYS2 bash 调用 build_ffmpeg_msvc.sh 编译
    final msvc = src('native/rdp/scripts/build_ffmpeg_msvc.sh');
    expect(ps, contains('build_ffmpeg_msvc.sh'));
    for (final ffmpeg in [sh, msvc]) {
      expect(ffmpeg, contains('--enable-decoder=h264'));
      expect(ffmpeg, contains('--enable-parser=h264'));
      expect(ffmpeg, contains('--disable-autodetect'));
      expect(ffmpeg, contains('set -euo pipefail'));
    }
    for (final script in [sh, ps]) {
      expect(script, contains('-DWITH_VIDEO_FFMPEG=ON'));
      expect(script, contains('-DWITH_FFMPEG_HWACCEL=ON'));
      expect(script, contains('-DWITH_DSP_FFMPEG=OFF'));
      expect(script, contains('-DWITH_SWSCALE=ON'));
      // 编译选项变化后旧的 FreeRDP 缓存会重新编译
      expect(script, contains('freerdp-features'));
    }
    expect(sh, contains('--enable-hwaccel=h264_videotoolbox'));
    expect(sh, contains('--enable-hwaccel=h264_vaapi'));
    expect(msvc, contains('h264_d3d11va'));
    expect(msvc, contains('--toolchain=msvc'));
    // 普通 Windows 开发者终端未设置 MSYS2 PATH，路径转换前必须先加入工具目录。
    expect(msvc.indexOf(r'export PATH="/usr/bin:$PATH"'), greaterThanOrEqualTo(0));
    expect(msvc.indexOf(r'export PATH="/usr/bin:$PATH"'), lessThan(msvc.indexOf(r'SRC="$(cygpath')));
    expect(msvc, contains(r'export MSYS2_ENV_CONV_EXCL="${MSYS2_ENV_CONV_EXCL:+$MSYS2_ENV_CONV_EXCL;}CL"'));
    expect(msvc, contains('export VSLANG=1033'));
    expect(msvc, contains('Visual Studio English language pack (en-US)'));
    // FFmpeg 与 FreeRDP 一样静态链接 MSVC 运行库；MSVC 的 link.exe 排在 MSYS2 的 link 之前
    expect(msvc, contains('--extra-cflags=-MT'));
    expect(msvc, contains(r'export PATH="$CL_DIR:/usr/bin:$PATH"'));
    // Windows 下 FreeRDP 按 MSVC 库名查找 FFmpeg
    expect(ps, contains('avcodec.lib'));
    expect(ps, contains('FFmpeg MSVC static library missing:'));
    expect(ps, isNot(contains(r'Move-Item -Force "$Prefix\lib\lib$lib.a"')));
    // FreeRDP 的硬解错误标签位于块末尾，MSVC C11 需要空语句。
    expect(ps, contains(r'fail_hwdevice_create:;$1'));
    expect(src('native/rdp/CMakeLists.txt'), contains(r'${DEPS_LIB}/avcodec.lib'));
    // Linux 链接 libva，macOS 链接 VideoToolbox
    expect(src('native/rdp/CMakeLists.txt'), contains('va va-drm'));
    expect(src('native/rdp/CMakeLists.txt'), contains('-framework VideoToolbox'));
  });

  test('原生库内置的探测帧与测试资源一致', () {
    // rmk_h264_probe_frame.h 中的字节数组由测试资源生成，两处必须同步
    final header = src('native/rdp/src/rmk_h264_probe_frame.h');
    final array = header.substring(header.indexOf('rmk_probe_frame[] = {'));
    final bytes = RegExp(r'0x([0-9a-f]{2}),').allMatches(array).map((m) => int.parse(m[1]!, radix: 16)).toList();
    expect(bytes, File('test/platform/fixtures/h264_320x240.h264').readAsBytesSync());
  });

  test('连接参数由 H.264 模块按探测结果与硬件解码设置决定，不再强制关闭 H.264', () {
    final rdp = src('native/rdp/src/remlark_rdp.c');
    expect(rdp, contains('rmk_h264_apply(s, rdp->hwdec_enabled)'));
    // 设置中关闭硬件解码时保持软件解码（SoftwareGdi 为 TRUE）
    expect(src('native/rdp/src/rmk_h264.c'), contains('FreeRDP_SoftwareGdi, !hardware'));
    expect(src('lib/modules/remote_desktop/rdp/rdp_client.dart'), contains('rmk_rdp_set_hwdec('));
    expect(src('lib/modules/workspace/session_launcher.dart'), contains('services.settings.rdpHardwareDecode'));
    expect(rdp, isNot(contains('FreeRDP_GfxH264, FALSE')));
    expect(rdp, isNot(contains('FreeRDP_GfxAVC444, FALSE')));
  });

  test('原生库探测：编入 H.264 解码器，设备类型与当前平台一致', () {
    if (!RdpClient.isAvailable) {
      markTestSkipped('RDP 原生库未编译（make rdp-lib）');
      return;
    }
    final h264 = RdpH264Support.probe();
    expect(h264.decoder, isTrue);
    final os = Platform.isMacOS ? 'macos' : (Platform.isWindows ? 'windows' : 'linux');
    expect(h264.hwType, platforms[os]);
    // VideoToolbox 是 macOS 系统组件，一定可用；Windows / Linux 取决于显卡与驱动（CI 无显卡时为软件解码）
    if (Platform.isMacOS) expect(h264.hardware, isTrue);
    expect(h264.describe(), contains(h264.hwType));
  });

  group('原生库实际解码（与连接相同的 FreeRDP AVC420 流程）', () {
    const w = 320, h = 240;
    final frame = File('test/platform/fixtures/h264_320x240.h264').readAsBytesSync();

    /// 检查 (x, y) 像素接近期望的 RGB 颜色（BGRA 排列，YUV 转换有少量误差）
    void expectColor(Uint8List bgra, int x, int y, int rgb, String reason) {
      final i = (y * w + x) * 4;
      final actual = [bgra[i + 2], bgra[i + 1], bgra[i]];
      final expected = [(rgb >> 16) & 0xFF, (rgb >> 8) & 0xFF, rgb & 0xFF];
      for (var c = 0; c < 3; c++) {
        expect((actual[c] - expected[c]).abs(), lessThanOrEqualTo(12), reason: '$reason ($x,$y) 实际 $actual 期望 $expected');
      }
    }

    /// 检查整帧：左右两半颜色正确
    void expectFrame(Uint8List? bgra, String reason) {
      expect(bgra, isNotNull, reason: '$reason 解码失败');
      for (final y in [10, 120, 230]) {
        expectColor(bgra!, 40, y, 0xE04020, '$reason 左半');
        expectColor(bgra, 280, y, 0x3080C0, '$reason 右半');
      }
    }

    test('软件解码颜色正确', () {
      if (!RdpClient.isAvailable) {
        markTestSkipped('RDP 原生库未编译（make rdp-lib）');
        return;
      }
      expectFrame(RdpH264Support.selfTest(frame, w, h, hardware: false), '软件解码');
    });

    test('硬件解码（不可用时自动软件解码）颜色正确，且与软件解码一致', () {
      if (!RdpClient.isAvailable) {
        markTestSkipped('RDP 原生库未编译（make rdp-lib）');
        return;
      }
      final support = RdpH264Support.probe();
      // ignore: avoid_print
      print('RDP H.264：${support.describe()}');
      final hw = RdpH264Support.selfTest(frame, w, h, hardware: true);
      expectFrame(hw, support.hardware ? '硬件解码（${support.hwType}）' : '硬件不可用回退软件解码');
      final sw = RdpH264Support.selfTest(frame, w, h, hardware: false)!;
      // 只比较颜色通道：alpha 由胶水库合成画面时统一置为 255
      var maxDiff = 0, at = 0;
      for (var i = 0; i < sw.length; i++) {
        if (i % 4 == 3) continue;
        final d = (sw[i] - hw![i]).abs();
        if (d > maxDiff) (maxDiff, at) = (d, i ~/ 4);
      }
      expect(maxDiff, lessThanOrEqualTo(4), reason: '硬件与软件解码结果差异过大：(${at % w},${at ~/ w})');
    });

    test('无效数据返回失败而不崩溃', () {
      if (!RdpClient.isAvailable) {
        markTestSkipped('RDP 原生库未编译（make rdp-lib）');
        return;
      }
      expect(RdpH264Support.selfTest(Uint8List(0), w, h, hardware: true), isNull);
      expect(RdpH264Support.selfTest(Uint8List.fromList(List.filled(64, 7)), w, h, hardware: true), isNull);
    });
  });
}
