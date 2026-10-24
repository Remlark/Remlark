// 启动外部进程，ARM runner 上进程启动慢，放宽默认 30 秒时限。
@Timeout(Duration(minutes: 3))
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../utils/version_fixture.dart';

/// 多平台测试 P-13：VERSION 解析、Flutter 版本参数、发布标签和三平台构建入口。
void main() {
  late Directory root;

  setUp(() => root = createVersionFixture('2.3.4-rc.2+17\r\n'));
  tearDown(() => root.deleteSync(recursive: true));

  /// 从其他工作目录调用，确认工具使用仓库位置而不是当前工作目录。
  Future<ProcessResult> version() => Process.run('python3', [
    '${root.path}/tools/utils/app_version.py',
    'json',
  ], workingDirectory: Directory.systemTemp.path);

  test('读取 VERSION 而非 pubspec，兼容 CRLF、预发布和各平台数字资源版本', () async {
    final result = await version();
    expect(result.exitCode, 0, reason: '${result.stderr}');
    expect(jsonDecode(result.stdout as String), {
      'name': '2.3.4-rc.2',
      'build_name': '2.3.4',
      'build_number': '17',
      'full': '2.3.4-rc.2+17',
      'resource': '2.3.4.17',
      'debian': '2.3.4~rc.2',
    });
    File('${root.path}/VERSION').writeAsStringSync('2.3.4\n');
    expect(jsonDecode((await version()).stdout as String)['build_number'], '1');
  });

  test('无效、越界或缺失 VERSION 立即失败，不使用 pubspec 默认版本', () async {
    for (final invalid in [
      '',
      'v2.3.4',
      '2.3',
      '02.3.4',
      '2.3.4+abc',
      '2.3.4+65536',
      '2.3.4\n3.4.5',
    ]) {
      File('${root.path}/VERSION').writeAsStringSync(invalid);
      final result = await version();
      expect(result.exitCode, isNot(0), reason: invalid);
      expect(result.stderr, contains('Invalid VERSION'));
    }
    File('${root.path}/VERSION').deleteSync();
    expect((await version()).stderr, contains('Cannot read VERSION'));
  });

  test('发布标签使用 VERSION 的版本号，不包含构建号', () async {
    for (final tag in ['v2.3.4-rc.2', 'v2.3.4-rc.2+17', 'v9.9.9']) {
      final result = await Process.run(
        'python3',
        ['${root.path}/tools/release/prepare.py', 'validate'],
        environment: {'RELEASE_TAG': tag},
      );
      expect(
        result.exitCode == 0,
        tag == 'v2.3.4-rc.2',
        reason: '${result.stderr}',
      );
    }
  });

  test('拒绝用命令行覆盖唯一版本，macOS 不允许给旧应用换版本名打包', () async {
    final override = await Process.run('python3', [
      '${root.path}/tools/utils/app_version.py',
      'flutter',
      'build',
      'macos',
      '--build-number=9',
    ]);
    expect(override.exitCode, isNot(0));
    expect(
      override.stderr,
      contains('Version arguments are managed by VERSION'),
    );
    final plist = File(
      '${root.path}/build/macos/Build/Products/Release/remlark.app/Contents/Info.plist',
    );
    plist.parent.createSync(recursive: true);
    plist.writeAsStringSync('''<?xml version="1.0" encoding="UTF-8"?>
<plist version="1.0"><dict>
<key>CFBundleShortVersionString</key><string>9.9.9</string>
<key>CFBundleVersion</key><string>9</string>
</dict></plist>''');
    final result = await Process.run('python3', [
      '${root.path}/tools/release/prepare.py',
      'macos',
    ]);
    expect(result.exitCode, isNot(0));
    expect(
      result.stderr,
      contains('application version does not match VERSION'),
    );
  });

  test('真实子进程收到版本参数，开发运行不传不支持的编译参数，退出码原样返回', () async {
    final bin = Directory('${root.path}/fake flutter')..createSync();
    File('${bin.path}/capture.py').writeAsStringSync('''
import json, sys
print(json.dumps(sys.argv[1:]))
sys.exit(7 if '--fail' in sys.argv else 0)
''');
    final executable = File(
      '${bin.path}/${Platform.isWindows ? 'flutter.cmd' : 'flutter'}',
    );
    executable.writeAsStringSync(
      Platform.isWindows
          ? '@echo off\r\npython3 "%~dp0capture.py" %*\r\n'
          : '#!/bin/sh\nexec python3 "\$(dirname "\$0")/capture.py" "\$@"\n',
    );
    if (!Platform.isWindows) {
      expect(
        (await Process.run('chmod', ['755', executable.path])).exitCode,
        0,
      );
    }
    // Windows 的 Path 键大小写不敏感，只保留一个实际 PATH 键。
    final pathKey = Platform.environment.keys.firstWhere(
      (key) => key.toUpperCase() == 'PATH',
    );
    final separator = Platform.isWindows ? ';' : ':';
    final environment = {
      pathKey: '${bin.path}$separator${Platform.environment[pathKey]}',
    };
    for (final command in [
      ['build', 'macos'],
      ['build', 'windows'],
      ['build', 'linux'],
      ['run', '-d', 'windows'],
    ]) {
      final result = await Process.run('python3', [
        '${root.path}/tools/utils/app_version.py',
        'flutter',
        ...command,
        '--fail',
      ], environment: environment);
      expect(result.exitCode, 7, reason: '${result.stdout}\n${result.stderr}');
      final args = (jsonDecode((result.stdout as String).trim()) as List)
          .cast<String>();
      expect(args.take(command.length), command);
      expect(args, contains('--dart-define=REMLARK_VERSION=2.3.4-rc.2+17'));
      expect(args.contains('--build-name=2.3.4'), command.first == 'build');
      expect(args.contains('--build-number=17'), command.first == 'build');
    }
  });

  test('编译入口覆盖三个平台，安装包复用唯一版本工具', () {
    final makefile = File('Makefile').readAsStringSync();
    for (final os in ['macos', 'windows', 'linux']) {
      expect(
        makefile,
        contains('tools/utils/app_version.py flutter build $os --release'),
      );
    }
    for (final file in [
      'linux/packaging/build.py',
      'windows/packaging/build.ps1',
      'tools/release/prepare.py',
    ]) {
      final script = File(file).readAsStringSync();
      expect(script, contains('app_version'));
      expect(script, isNot(contains('pubspec.yaml')));
    }
    expect(
      File('pubspec.yaml').readAsStringSync(),
      isNot(matches(RegExp(r'^version:', multiLine: true))),
    );
  });
}
