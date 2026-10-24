// 启动外部进程，ARM runner 上进程启动慢，放宽默认 30 秒时限。
@Timeout(Duration(minutes: 3))
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// 多平台测试 P-26：原生依赖下载先校验再解压，异常响应重试及镜像回退。
void main() {
  test('源码下载拒绝错误页和损坏包，重试回退且不覆盖已验证文件', () async {
    final result = await Process.run('python3', [
      'tools/testing/source_archive_test.py',
      '-v',
    ]);
    expect(result.exitCode, 0, reason: '${result.stdout}\n${result.stderr}');
    expect('${result.stdout}${result.stderr}', contains('OK'));
  });

  test('三平台使用统一下载校验，Windows zlib 使用双来源及固定 SHA-256', () {
    for (final script in ['build.ps1', 'build.sh']) {
      final source = File('native/rdp/scripts/$script').readAsStringSync();
      expect(source, contains('source_archive.py'));
      expect(source, contains('--root'));
      expect(source, isNot(contains('Invoke-WebRequest')));
      expect(source, isNot(contains('curl -fsSL')));
    }
    final windows = File('native/rdp/scripts/build.ps1').readAsStringSync();
    expect(windows, contains('github.com/madler/zlib/releases/download/'));
    expect(windows, contains('https://zlib.net/fossils/'));
    // 下载校验提前，避免编译 OpenSSL 数分钟后才发现其他源码不可用。
    expect(
      windows.indexOf('Fetch "https://github.com/madler/zlib/'),
      lessThan(windows.indexOf('# 1. OpenSSL')),
    );
    expect(
      windows.indexOf('Fetch "https://ffmpeg.org/'),
      lessThan(windows.indexOf('# 1. OpenSSL')),
    );
    expect(
      windows,
      contains(
        '9a93b2b7dfdac77ceba5a558a580e74667dd6fede4585b91eefb60f03b72df23',
      ),
    );
  });
}
