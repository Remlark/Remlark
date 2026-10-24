// 启动外部进程，ARM runner 上进程启动慢，放宽默认 30 秒时限。
@Timeout(Duration(minutes: 3))
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// 多平台测试 P-22：运行中构建保护；三平台逻辑与本机真实进程的拒绝/放行。
void main() {
  test('构建覆盖保护的路径、进程、错误处理和统一入口回归', () async {
    final result = await Process.run('python3', [
      'tools/testing/build_guard_test.py',
      '-v',
    ]);
    expect(result.exitCode, 0, reason: '${result.stdout}\n${result.stderr}');
    expect('${result.stdout}${result.stderr}', contains('OK'));
  });
}
