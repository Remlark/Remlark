import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:remlark/modules/hosts/host_model.dart';
import 'package:remlark/modules/hosts/ui/host_form.dart';

import '../helpers/platform_tools.dart';
import '../utils/source_text.dart';

/// 多平台测试 P-34：RDP 远程声音（见 docs/multi-platform-testing.md）
/// 三平台共用 rdpsnd 通道，播放后端按平台在 FreeRDP 编译时开启：
/// macOS AudioToolbox（WITH_MACAUDIO）、Windows winmm（WITH_WINMM）、Linux PulseAudio + ALSA。
/// 实际出声需要真实 Windows 服务器，按手工测试 M-37 验证。
void main() {
  // 源码断言含换行片段，统一 LF 以兼容 Windows CRLF 检出
  String src(String path) => readSourceText(path);

  test('连接时按主机设置开启 AudioPlayback，由 FreeRDP 加载 rdpsnd 并自动选择后端', () {
    final rdp = src('native/rdp/src/remlark_rdp.c');
    expect(rdp, contains('rmk_apply_audio(s, rdp->audio_enabled)'));
    expect(rdp, contains('rdp->audio_enabled = TRUE;'), reason: '原生默认开启，与 Dart 默认一致');
    // 由 FreeRDP 按 AudioPlayback 加载 rdpsnd，不写死 sys:xxx，否则 Linux 上 PulseAudio 不可用时无法退回 ALSA
    expect(rdp, contains('return freerdp_settings_set_bool(s, FreeRDP_AudioPlayback, enabled);'));
    expect(rdp, isNot(contains('"sys:')));
    // FreeRDP 3.32.2：AudioPlayback 为 TRUE 时加载静态与动态 rdpsnd，并据此开启 rdpdr
    final cmdline = File('native/rdp/.deps/FreeRDP-3.32.2/client/common/cmdline.c');
    if (cmdline.existsSync()) {
      final c = readSourceText(cmdline.path);
      expect('{ FreeRDP_AudioPlayback, RDPSND_CHANNEL_NAME, nullptr },'.allMatches(c).length, 2);
      expect(c, contains('/* rdpsnd requires rdpdr to be registered */'));
    }
    expect(src('native/rdp/src/remlark_rdp.h'), contains('RMK_API void rmk_rdp_set_audio(RmkRdp* rdp, int32_t enabled);'));
    expect(src('lib/modules/remote_desktop/rdp/rdp_bindings.dart'), contains('external void rmk_rdp_set_audio('));
    expect(src('lib/modules/remote_desktop/rdp/rdp_client.dart'), contains('rmk_rdp_set_audio(_handle, o.audio ? 1 : 0);'));
    expect(src('lib/modules/remote_desktop/rdp/rdp_session.dart'), contains("audio: host.extra['audio'] != false,"));
  });

  test('构建脚本：三平台都编译 rdpsnd，按平台开启播放后端', () {
    final sh = src('native/rdp/scripts/build.sh');
    final ps = src('native/rdp/scripts/build.ps1');
    for (final script in [sh, ps]) {
      expect(script, isNot(contains('-DCHANNEL_RDPSND=OFF')));
      expect(script, isNot(contains('-DWITH_WINMM=OFF')));
      expect(script, isNot(contains('-DWITH_MACAUDIO=OFF')));
    }
    // Linux：PulseAudio 优先、ALSA 兜底；macOS 不开启这两个后端
    expect(sh, contains('AUDIO_OPTS=(-DWITH_PULSE=OFF -DWITH_ALSA=OFF)'));
    expect(sh, contains('[[ "\$PLATFORM" == linux ]] && AUDIO_OPTS=(-DWITH_PULSE=ON -DWITH_ALSA=ON)'));
    expect(sh, contains('"\${AUDIO_OPTS[@]}"'));
    expect(sh, contains('pkg-config --exists libpulse alsa'));
    // 开启后端后旧的 FreeRDP 缓存需要重新编译
    expect(sh, contains('FREERDP_FEATURES="h264-ffmpeg-hwaccel-1;audio-1"'));
    // 胶水库在 Linux 链接系统 PulseAudio / ALSA，macOS 链接 AudioToolbox
    final cmake = src('native/rdp/CMakeLists.txt');
    expect(cmake, contains('target_link_libraries(remlark_rdp PRIVATE pulse asound)'));
    expect(cmake, contains('"-framework AudioToolbox"'));
    // CI 与文档安装开发包，Linux 测试 runner 安装运行库
    expect(src('.github/workflows/release.yml'), contains('libpulse-dev libasound2-dev'));
    expect(src('.github/workflows/test.yml'), contains('libpulse0 libasound2t64'));
  });

  test('当前平台已编译的 FreeRDP 开启了对应播放后端', () {
    final cache = nativeBuildFile(p.join('freerdp-build', 'CMakeCache.txt'));
    if (!cache.existsSync()) {
      markTestSkipped('未在本机编译 FreeRDP');
      return;
    }
    final text = cache.readAsStringSync();
    expect(text, contains('CHANNEL_RDPSND_CLIENT:BOOL=ON'));
    final backends = Platform.isMacOS
        ? ['WITH_MACAUDIO']
        : Platform.isWindows
        ? ['WITH_WINMM']
        : ['WITH_PULSE', 'WITH_ALSA'];
    // 命令行 -D 传入的选项在 CMakeCache 中可能记为 UNINITIALIZED 类型
    for (final b in backends) {
      expect(text, matches(RegExp('^$b:(BOOL|UNINITIALIZED)=ON\$', multiLine: true)), reason: b);
    }
  });

  test('主机设置：播放远程声音默认开启，关闭后保存到 extra', () {
    final fresh = HostForm(null, HostProtocol.rdp, null);
    fresh.address.text = '10.0.0.2';
    expect(fresh.audio, isTrue);
    fresh.audio = false;
    final saved = fresh.build();
    expect(saved.extra['audio'], isFalse);
    // 旧主机没有该字段时按开启处理
    expect(HostForm(saved.copyWith(extra: const {}), HostProtocol.rdp, null).audio, isTrue);
    expect(HostForm(saved, HostProtocol.rdp, null).audio, isFalse);
  });
}
