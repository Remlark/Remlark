import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// 多平台测试 P-23：服务端六路发布矩阵、原生架构和完整 bundle 打包。
void main() {
  test('六种服务端归档保留依赖，拒绝缺失和混用架构', () async {
    final result = await Process.run('python3', [
      'tools/testing/server_bundle_test.py',
      '-v',
    ]);
    expect(result.exitCode, 0, reason: '${result.stdout}\n${result.stderr}');
    expect('${result.stdout}${result.stderr}', contains('OK'));
  });

  test('独立六路服务端构建均测试和解包启动，发布等待两组构建', () {
    final workflow = File('.github/workflows/release.yml')
        .readAsLinesSync()
        .join('\n');
    final server = workflow.substring(
      workflow.indexOf('  server:'),
      workflow.indexOf('  publish:'),
    );
    for (final entry in [
      'platform: linux, arch: x64, runner: ubuntu-24.04',
      'platform: linux, arch: arm64, runner: ubuntu-24.04-arm',
      'platform: windows, arch: x64, runner: windows-2022',
      'platform: windows, arch: arm64, runner: windows-11-arm',
      'platform: macos, arch: x64, runner: macos-15-intel',
      'platform: macos, arch: arm64, runner: macos-15',
    ]) {
      expect(server, contains(entry));
    }
    expect(server, contains('dart pub get --enforce-lockfile'));
    expect(server, contains('dart analyze\n          dart test'));
    expect(server, contains('dart build cli -t bin/server.dart'));
    expect(server, contains('tools/release/server_bundle.py'));
    expect(server, contains('--smoke'));
    expect(server, contains('packages-server-'));
    expect(workflow, contains('needs: [build, server]'));
  });
}
