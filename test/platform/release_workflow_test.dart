import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../utils/version_fixture.dart';

/// 多平台测试 P-10：版本标签、发布附件完整性及失败时阻止发布。
void main() {
  test('手工构建默认不发布，三个平台编译后都重新执行平台测试', () {
    // readAsLinesSync 同时兼容 Windows CRLF 与 macOS / Linux LF。
    final workflow = File('.github/workflows/release.yml')
        .readAsLinesSync()
        .join('\n');
    // 手工验证与正式发布共用矩阵，默认只构建分支；版本标签仍走正式发布。
    expect(workflow, contains('build_only:'));
    expect(workflow, contains('default: true\n        type: boolean'));
    expect(
      workflow,
      contains('ref: \u0024{{ inputs.tag || github.ref_name }}'),
    );
    final releaseGuard =
        "if: github.event_name != 'workflow_dispatch' || !inputs.build_only";
    expect(releaseGuard.allMatches(workflow).length, 4);
    expect(
      workflow.substring(workflow.indexOf('  publish:')),
      contains(releaseGuard),
    );
    // 两个构建后入口分别覆盖 Windows 和 macOS / Linux，确保加载本轮原生库。
    final postBuild = workflow.substring(
      workflow.indexOf('      # 原生库编译后'),
      workflow.indexOf('  server:'),
    );
    expect('make test-platform'.allMatches(postBuild).length, 2);
    expect("RMK_REQUIRE_RDP_NATIVE: '1'".allMatches(postBuild).length, 2);
    for (final runner in [
      'ubuntu-24.04',
      'ubuntu-24.04-arm',
      'windows-2022',
      'windows-11-arm',
      'macos-15',
    ]) {
      expect(workflow, contains('runner: $runner }'));
    }
  });

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
    final root = createVersionFixture('1.2.3+4\n');
    addTearDown(() => root.deleteSync(recursive: true));
    final script = File('${root.path}/tools/release/prepare.py');
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
    final root = createVersionFixture('1.2.3+4\n');
    addTearDown(() => root.deleteSync(recursive: true));
    final script = File('${root.path}/tools/release/prepare.py');
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
    // 桌面端齐全仍不得发布：六个服务端附件必须一起生成校验清单。
    final incomplete = await Process.run(
      'python3',
      [script.path, 'manifest'],
      environment: {'RELEASE_TAG': 'v1.2.3'},
    );
    expect(incomplete.exitCode, isNot(0));
    expect(incomplete.stderr, contains('remlark-sync-server-'));
    expect(File('${dist.path}/SHA256SUMS').existsSync(), isFalse);
    for (final platform in ['macos', 'windows', 'linux']) {
      for (final arch in ['x64', 'arm64']) {
        final extension = platform == 'windows' ? 'zip' : 'tar.gz';
        final name = 'remlark-sync-server-1.2.3-$platform-$arch.$extension';
        names.add(name);
        File('${dist.path}/$name').writeAsStringSync('abc');
      }
    }
    final result = await Process.run(
      'python3',
      [script.path, 'manifest'],
      environment: {'RELEASE_TAG': 'v1.2.3'},
    );
    expect(result.exitCode, 0, reason: '${result.stderr}');
    final lines = File('${dist.path}/SHA256SUMS').readAsLinesSync();
    expect(lines.length, 16);
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
