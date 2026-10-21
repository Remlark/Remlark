import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// 多平台测试 P-10：版本标签、发布附件完整性及失败时阻止发布。
void main() {
  test('版本标签不匹配时拒绝发布', () async {
    final result = await Process.run(
      'python3',
      ['tools/release/prepare.py', 'validate'],
      environment: {'RELEASE_TAG': 'v0.0.0'},
    );
    expect(result.exitCode, isNot(0));
    expect(result.stderr, contains('RELEASE_TAG must equal'));
  });

  test('附件缺失时拒绝生成发布清单', () async {
    final root = Directory.systemTemp.createTempSync('remlark release ');
    addTearDown(() => root.deleteSync(recursive: true));
    final script = File('${root.path}/tools/release/prepare.py');
    script.parent.createSync(recursive: true);
    script.writeAsStringSync(
      File('tools/release/prepare.py').readAsStringSync(),
    );
    File('${root.path}/pubspec.yaml').writeAsStringSync('version: 1.2.3+4\n');
    Directory('${root.path}/dist').createSync();
    final result = await Process.run(
      'python3',
      [script.path, 'manifest'],
      environment: {'RELEASE_TAG': 'v1.2.3'},
    );
    expect(result.exitCode, isNot(0));
    expect(result.stderr, contains('missing or empty release asset'));
    expect(File('${root.path}/dist/SHA256SUMS').existsSync(), isFalse);
  });

  test('完整矩阵生成可校验的 SHA256SUMS', () async {
    final root = Directory.systemTemp.createTempSync('remlark complete ');
    addTearDown(() => root.deleteSync(recursive: true));
    final script = File('${root.path}/tools/release/prepare.py');
    script.parent.createSync(recursive: true);
    script.writeAsStringSync(
      File('tools/release/prepare.py').readAsStringSync(),
    );
    File('${root.path}/pubspec.yaml').writeAsStringSync('version: 1.2.3+4\n');
    final dist = Directory('${root.path}/dist')..createSync();
    final names = ['remlark-1.2.3-macos-universal.dmg', 'remlark-macos.zip'];
    for (final arch in ['x64', 'arm64']) {
      names.addAll([
        'remlark-1.2.3-windows-$arch-setup.exe',
        'remlark-windows-$arch.zip',
        'remlark-1.2.3-linux-${arch == 'x64' ? 'amd64' : 'arm64'}.deb',
        'remlark-linux-$arch.tar.gz',
      ]);
    }
    for (final name in names) {
      File('${dist.path}/$name').writeAsStringSync('abc');
    }
    final result = await Process.run(
      'python3',
      [script.path, 'manifest'],
      environment: {'RELEASE_TAG': 'v1.2.3'},
    );
    expect(result.exitCode, 0, reason: '${result.stderr}');
    final lines = File('${dist.path}/SHA256SUMS').readAsLinesSync();
    expect(lines.length, 10);
    for (final line in lines) {
      expect(
        line,
        startsWith(
          'ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad  ',
        ),
      );
    }
  });
}
