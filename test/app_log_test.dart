import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:remlark/utils/app_log.dart';

void main() {
  test('日志：初始化前的记录补写入文件，按级别与模块格式化，清理过期文件', () async {
    final dir = Directory.systemTemp.createTempSync('rmk_log');
    addTearDown(() async {
      await AppLog.close();
      dir.deleteSync(recursive: true);
    });
    final logs = Directory('${dir.path}/logs')..createSync();
    final old = File('${logs.path}/remlark-2000-01-01.log')..writeAsStringSync('old');
    old.setLastModifiedSync(DateTime.now().subtract(const Duration(days: 30)));

    AppLog.echo = false;
    AppLog.i('early', '初始化前');
    await AppLog.init(dir);
    AppLog.w('vnc', '慢更新 ${'x' * 5000}');
    AppLog.e('ssh', '失败', StateError('boom'), StackTrace.current);
    await AppLog.flush();

    expect(old.existsSync(), isFalse, reason: '超过保留天数的日志应删除');
    final files = logs.listSync().whereType<File>().toList();
    expect(files, hasLength(1));
    final text = files.single.readAsStringSync();
    expect(text, contains('I [early] 初始化前'));
    expect(text, contains('W [vnc] 慢更新'));
    expect(text, contains('…(5004)'), reason: '超长消息截断');
    expect(text, contains('E [ssh] 失败 | Bad state: boom'));
    expect(RegExp(r'^\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}\.\d{3} ', multiLine: true).hasMatch(text), isTrue);
  });
}
