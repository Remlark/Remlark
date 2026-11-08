// 启动外部进程，ARM runner 上进程启动慢，放宽默认 30 秒时限。
@Timeout(Duration(minutes: 3))
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// 多平台测试 P-33：sqlite3 预编译库经 API 预取到钩子缓存，避免 releases/download 5xx 被误报为哈希不符。
void main() {
  test('三平台附件命名、缓存布局、来源回退与哈希校验', () async {
    final result = await Process.run('python3', [
      'tools/testing/sqlite_assets_test.py',
      '-v',
    ]);
    expect(result.exitCode, 0, reason: '${result.stdout}\n${result.stderr}');
  });

  test('工作流在首次平台测试或服务端测试前按矩阵系统与架构预取', () {
    const prefetch =
        r'sqlite_assets.py . --os ${{ matrix.platform }} --arch ${{ matrix.arch }}';
    const token = r'GH_TOKEN: ${{ github.token }}';
    final tests = File('.github/workflows/test.yml')
        .readAsLinesSync()
        .join('\n');
    final release = File('.github/workflows/release.yml')
        .readAsLinesSync()
        .join('\n');
    // 预取依赖 pub get 生成的 package_config，且必须早于触发钩子的测试命令。
    expect(tests.indexOf(prefetch), greaterThan(tests.indexOf('flutter pub get')));
    expect(
      tests.indexOf(prefetch),
      lessThan(tests.indexOf('run: make test-platform')),
    );
    expect(tests, contains(token));
    final desktop = release.substring(
      release.indexOf('  build:'),
      release.indexOf('  server:'),
    );
    // bash 与 Windows pwsh 两个依赖入口；macOS 矩阵 arch 为 universal，预取双架构。
    expect(prefetch.allMatches(desktop).length, 2);
    expect(token.allMatches(desktop).length, 2);
    expect(desktop, contains('platform: macos, arch: universal'));
    expect(desktop, contains("throw 'sqlite3 asset prefetch failed'"));
    for (final entry in [
      ['make deps\n', 'make test-platform'],
      ["throw 'Flutter dependencies failed' }\n", 'make test-platform'],
    ]) {
      final start = desktop.indexOf(entry[0]);
      final at = desktop.indexOf(prefetch, start);
      expect(at, greaterThan(start));
      expect(at, lessThan(desktop.indexOf(entry[1], start)));
    }
    final server = release.substring(release.indexOf('  server:'));
    expect(server, contains(token));
    expect(
      server.indexOf(prefetch),
      allOf(
        greaterThan(server.indexOf('dart pub get')),
        lessThan(server.indexOf('dart test')),
      ),
    );
    // 上一版只重试预热钩子，无法绕过持续故障的下载入口，不再保留。
    expect('$tests\n$release', isNot(contains('native-assets')));
  });
}
