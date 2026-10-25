// 启动外部进程，ARM runner 上进程启动慢，放宽默认 30 秒时限。
@Timeout(Duration(minutes: 3))
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// 多平台测试 P-31：Release 优先使用在线的自托管 macOS runner，离线时回退托管 runner。
void main() {
  test('在线选择自托管，离线、无令牌或查询失败回退托管 runner', () async {
    final result = await Process.run('python3', [
      'tools/testing/pick_runner_test.py',
      '-v',
    ]);
    expect(result.exitCode, 0, reason: '${result.stdout}\n${result.stderr}');
  });

  test('桌面 macOS 与服务端 arm64 使用选择结果，服务端 x64 固定托管', () {
    final workflow = File('.github/workflows/release.yml')
        .readAsLinesSync()
        .join('\n');
    final pick = workflow.substring(
      workflow.indexOf('  pick-runner:'),
      workflow.indexOf('  build:'),
    );
    expect(pick, contains('runs-on: ubuntu-24.04'));
    expect(
      pick,
      contains('RUNNER_STATUS_TOKEN: \u0024{{ secrets.RUNNER_STATUS_TOKEN }}'),
    );
    expect(pick, contains('--label remlark-macmini --fallback macos-15'));
    const runsOn =
        "runs-on: \u0024{{ matrix.runner == 'macos-15' && needs.pick-runner.outputs.macos || matrix.runner }}";
    for (final job in ['build', 'server']) {
      final start = workflow.indexOf('  $job:');
      final body = workflow.substring(
        start,
        workflow.indexOf('    steps:', start),
      );
      expect(body, contains('needs: [pick-runner]'), reason: job);
      expect(body, contains(runsOn), reason: job);
    }
    // 只有 macos-15 项会被替换；Intel 服务端始终走 GitHub 托管。
    expect(
      workflow,
      contains('{ platform: macos, arch: x64, runner: macos-15-intel }'),
    );
    expect(workflow, isNot(contains('runs-on: remlark-macmini')));
  });
}
