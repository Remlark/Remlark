import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:remlark/utils/archive/archive_extractor.dart';
import 'package:remlark/utils/archive/archive_extractor_posix.dart';
import 'package:remlark/utils/archive/archive_extractor_windows.dart';

import '../helpers/platform_tools.dart';

/// 多平台测试 P-03：用当前系统的解压工具解压 .tar.gz / .zip（见 docs/multi-platform-testing.md）
void main() {
  late Directory tmp;

  setUp(
    () async => tmp = await Directory.systemTemp.createTemp('rmk-archive-'),
  );
  tearDown(() async => tmp.delete(recursive: true));

  /// 准备待打包的源目录：含子目录与中文文件名
  Directory source() {
    final src = Directory(p.join(tmp.path, 'src'));
    Directory(p.join(src.path, 'bin')).createSync(recursive: true);
    File(p.join(src.path, 'bin', 'tool'))
        .writeAsStringSync('#!/bin/sh\necho ok\n');
    File(p.join(src.path, '说明.txt')).writeAsStringSync('中文内容');
    return src;
  }

  /// 检查解压结果
  void expectExtracted(Directory dest) {
    expect(File(p.join(dest.path, 'bin', 'tool')).existsSync(), isTrue);
    expect(File(p.join(dest.path, '说明.txt')).readAsStringSync(), '中文内容');
  }

  test('解压实现：Windows 使用 Dart 流式解码，其余平台使用 tar / unzip', () {
    final e = ArchiveExtractor.current();
    expect(
      e,
      Platform.isWindows
          ? isA<WindowsArchiveExtractor>()
          : isA<PosixArchiveExtractor>(),
    );
  });

  test('解压 .tar.gz：还原目录结构与中文文件名，POSIX 平台保留可执行权限', () async {
    final src = source();
    if (!Platform.isWindows) {
      await Process.run('chmod', ['755', p.join(src.path, 'bin', 'tool')]);
    }
    final archive = p.join(tmp.path, 'a.tar.gz');
    // Windows ARM64 系统 tar 的创建路径会在中文文件名上崩溃，用独立工具生成标准 UTF-8 夹具。
    final r = Platform.isWindows
        ? await Process.run('python3', [
            '-c',
            'import tarfile,sys; t=tarfile.open(sys.argv[1], "w:gz", format=tarfile.PAX_FORMAT); t.add(sys.argv[2], arcname="."); t.close()',
            archive,
            src.path,
          ])
        : await Process.run(systemTar(), [
            '-czf',
            archive,
            '-C',
            src.path,
            '.',
          ]);
    expect(r.exitCode, 0, reason: '${r.stderr}');

    final dest = Directory(p.join(tmp.path, 'out'))..createSync();
    await ArchiveExtractor.current().extract(File(archive), dest);
    expectExtracted(dest);
    if (!Platform.isWindows) {
      // 三平台都验证 Windows 的纯 Dart 解码，提前发现 Unicode 和流式读取回归。
      final windowsDest = Directory(p.join(tmp.path, 'windows-out'))
        ..createSync();
      await WindowsArchiveExtractor().extract(File(archive), windowsDest);
      expectExtracted(windowsDest);
    }
    if (!Platform.isWindows) {
      final mode = File(p.join(dest.path, 'bin', 'tool')).statSync().mode;
      expect(mode & 0x40, isNot(0), reason: '所有者可执行位丢失');
    }
  });

  test('解压 .zip（Windows 上 Node.js 安装包为 zip）', () async {
    final src = source();
    final archive = p.join(tmp.path, 'a.zip');
    final ProcessResult r;
    if (Platform.isWindows) {
      r = await Process.run(
        'powershell',
        [
          '-NoProfile',
          '-Command',
          'Compress-Archive -Path (Join-Path \$env:RMK_SRC "*") -DestinationPath \$env:RMK_DEST',
        ],
        environment: {'RMK_SRC': src.path, 'RMK_DEST': archive},
      );
    } else {
      try {
        r = await Process.run('zip', [
          '-qr',
          archive,
          '.',
        ], workingDirectory: src.path);
      } on ProcessException {
        return markTestSkipped('系统没有 zip 命令');
      }
    }
    expect(r.exitCode, 0, reason: '${r.stderr}');

    final dest = Directory(p.join(tmp.path, 'out'))..createSync();
    await ArchiveExtractor.current().extract(File(archive), dest);
    expectExtracted(dest);
    if (!Platform.isWindows) {
      // 三平台都验证 Windows 的纯 Dart 解码，提前发现 Unicode 和流式读取回归。
      final windowsDest = Directory(p.join(tmp.path, 'windows-out'))
        ..createSync();
      await WindowsArchiveExtractor().extract(File(archive), windowsDest);
      expectExtracted(windowsDest);
    }
  });

  test('压缩包损坏时抛出 ProcessException', () async {
    final archive = File(p.join(tmp.path, 'bad.tar.gz'))
      ..writeAsStringSync('not an archive');
    final dest = Directory(p.join(tmp.path, 'out'))..createSync();
    await expectLater(
      ArchiveExtractor.current().extract(archive, dest),
      throwsA(isA<ProcessException>()),
    );
  });
}
