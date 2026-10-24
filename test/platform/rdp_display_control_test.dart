import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:remlark/utils/platform_utils.dart';

/// 多平台测试 P-21：三平台共用的 RDP 显示控制必须等待服务端能力协商。
void main() {
  final source = File('native/rdp/src/remlark_rdp.c').readAsStringSync();

  test('通道重建注册能力回调，断开与释放清除能力状态', () {
    final attach = source.substring(
      source.indexOf('static void rmk_on_channel_connected'),
      source.indexOf('static void rmk_on_channel_disconnected'),
    );
    final detach = source.substring(
      source.indexOf('static void rmk_on_channel_disconnected'),
      source.indexOf('/* ---------- 连接回调'),
    );
    final disconnect = source.substring(
      source.indexOf('void rmk_rdp_disconnect('),
      source.indexOf('void rmk_rdp_free('),
    );
    expect(attach, contains('rdp->disp_caps_received = FALSE;'));
    expect(
      attach,
      contains('rdp->disp->DisplayControlCaps = rmk_display_control_caps;'),
    );
    for (final code in [detach, disconnect]) {
      expect(code, contains('rdp->disp_caps_received = FALSE;'));
      expect(code, contains('rdp->disp = NULL;'));
    }
  });

  test('实际 C 函数：协商前不发送、尺寸合并、断线与重定向隔离', () async {
    // 编译生产函数本身，用假通道模拟严格服务端，避免依赖真实桌面及登录凭据。
    final compiler = PlatformUtils.which(Platform.isWindows ? 'cl' : 'cc');
    if (compiler == null) {
      if (Platform.environment['RMK_REQUIRE_RDP_NATIVE'] == '1') {
        fail('原生构建环境必须提供 C 编译器');
      }
      markTestSkipped('需要 C 编译器（Windows 开发者终端 cl，macOS/Linux cc）');
      return;
    }
    final dir = Directory.systemTemp.createTempSync('rmk_display_caps_');
    addTearDown(() => dir.deleteSync(recursive: true));
    final functions = source.substring(
      source.indexOf('static void rmk_apply_pending_resize'),
      source.indexOf('/* 注册通道回调'),
    );
    final harness = File('test/fixtures/rdp_display_control_harness.c')
        .readAsStringSync();
    final input = File(p.join(dir.path, 'display_test.c'));
    input.writeAsStringSync(
      harness.replaceFirst('/* PRODUCTION_FUNCTIONS */', functions),
    );
    final binary = p.join(
      dir.path,
      Platform.isWindows ? 'display_test.exe' : 'display_test',
    );
    final compiled = await Process.run(
      compiler,
      Platform.isWindows
          ? ['/nologo', '/utf-8', input.path, '/Fe:$binary']
          : [
              '-std=c11',
              '-Wall',
              '-Wextra',
              '-Werror',
              input.path,
              '-o',
              binary,
            ],
      workingDirectory: dir.path,
    );
    expect(
      compiled.exitCode,
      0,
      reason: '${compiled.stdout}\n${compiled.stderr}',
    );
    final result = await Process.run(binary, []);
    expect(result.exitCode, 0, reason: '${result.stdout}\n${result.stderr}');
  });
}
