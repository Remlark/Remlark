// 启动外部进程，ARM runner 上进程启动慢，放宽默认 30 秒时限。
@Timeout(Duration(minutes: 3))
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// 多平台测试 P-28：CI 网络安装命令统一有限重试，三平台入口一致。
void main() {
  test('重试工具退避、清理半成品并传递最后退出码', () async {
    final result = await Process.run('python3', [
      'tools/testing/retry_command_test.py',
      '-v',
    ]);
    expect(result.exitCode, 0, reason: '${result.stdout}\n${result.stderr}');
  });

  test('Flutter SDK 托管每次克隆，自托管缓存复用并清理半成品与旧版本', () async {
    final result = await Process.run('python3', [
      'tools/testing/flutter_sdk_test.py',
      '-v',
    ]);
    expect(result.exitCode, 0, reason: '${result.stdout}\n${result.stderr}');
  });

  test('发布与平台专项工作流的网络安装均经过重试工具', () {
    const retry = 'python3 tools/utils/retry_command.py';
    final release = File('.github/workflows/release.yml')
        .readAsLinesSync()
        .join('\n');
    final tests = File('.github/workflows/test.yml')
        .readAsLinesSync()
        .join('\n');
    // Flutter 克隆失败必须先清理半成品目录，否则下一次 clone 会因目录非空失败。
    const clone =
        '$retry --clean "\$RUNNER_TEMP/flutter" -- git clone --depth 1';
    expect(tests, contains(clone));
    // 发布工作流经 flutter_sdk.py 安装（内部同样调用 run_with_retry 并清理半成品）。
    expect(
      release,
      contains(
        'python3 tools/utils/flutter_sdk.py --version "\$FLUTTER_VERSION" --github-path "\$GITHUB_PATH"',
      ),
    );
    for (final command in [
      '$retry -- sudo apt-get update',
      '$retry -- sudo apt-get install -y',
      '$retry -- brew install cmake ninja nasm',
      '$retry -- choco install make strawberryperl',
      '$retry -- choco install msys2',
      "$retry -- C:\\msys64\\usr\\bin\\bash.exe -lc 'pacman",
      '$retry -- flutter config',
      '$retry -- gh release upload',
      '$retry -- gh release edit',
    ]) {
      expect(release, contains(command), reason: command);
    }
    for (final command in [
      '$retry -- sudo apt-get update',
      '$retry -- choco install make',
      '$retry -- flutter pub get --enforce-lockfile',
    ]) {
      expect(tests, contains(command), reason: command);
    }
    // 不允许遗漏未包装的网络安装命令。
    for (final line in '$release\n$tests'.split('\n')) {
      final trimmed = line.trim();
      for (final bare in [
        'git clone',
        'sudo apt-get',
        'brew install',
        'choco install',
      ]) {
        expect(trimmed.startsWith(bare), isFalse, reason: line);
      }
    }
  });
}
