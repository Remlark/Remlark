// 启动外部进程，ARM runner 上进程启动慢，放宽默认 30 秒时限。
@Timeout(Duration(minutes: 3))
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:remlark/utils/app_log.dart';

import '../helpers/platform_tools.dart';

/// 多平台测试 P-07：Dart 子进程启动与日志文件句柄释放，在三个桌面平台执行。
void main() {
  test('使用真实 Dart 可执行文件启动子进程', () async {
    final result = await Process.run(dartExecutable(), ['--version']);
    expect(result.exitCode, 0);
    expect('${result.stdout}${result.stderr}', contains('Dart SDK version'));
  });

  test('重新初始化日志时关闭旧目录，关闭后可以删除当前目录', () async {
    final root = Directory.systemTemp.createTempSync('rmk_log_lifecycle');
    final previousEcho = AppLog.echo;
    AppLog.echo = false;
    addTearDown(() async {
      await AppLog.close();
      AppLog.echo = previousEcho;
      if (root.existsSync()) root.deleteSync(recursive: true);
    });
    final first = Directory('${root.path}/first')..createSync();
    final second = Directory('${root.path}/second')..createSync();
    await AppLog.init(first);
    AppLog.i('test', '第一段日志');
    await AppLog.init(second);
    expect(Directory('${first.path}/logs').listSync().whereType<File>().single.readAsStringSync(), contains('第一段日志'));
    first.deleteSync(recursive: true);
    AppLog.i('test', '第二段日志');
    await AppLog.close();
    expect(Directory('${second.path}/logs').listSync().whereType<File>().single.readAsStringSync(), contains('第二段日志'));
    second.deleteSync(recursive: true);
  });
}
