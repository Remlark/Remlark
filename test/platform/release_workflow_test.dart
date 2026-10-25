// 启动外部进程，ARM runner 上进程启动慢，放宽默认 30 秒时限。
@Timeout(Duration(minutes: 3))
library;

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
      'macos-15',
    ]) {
      expect(workflow, contains('runner: $runner }'));
    }
    // 桌面不再构建 Windows ARM64；windows-11-arm 只保留在服务端矩阵。
    final desktop = workflow.substring(
      workflow.indexOf('  build:'),
      workflow.indexOf('  server:'),
    );
    expect(desktop, isNot(contains('windows-11-arm')));
    expect(
      workflow.substring(workflow.indexOf('  server:')),
      contains('platform: windows, arch: arm64, runner: windows-11-arm }'),
    );
  });

  test('macOS 逐个架构校验通用二进制，缺少架构时报出具体架构', () async {
    final root = Directory.systemTemp.createTempSync('remlark lipo 中文 ');
    addTearDown(() => root.deleteSync(recursive: true));
    final source = File('${root.path}/main.c')
      ..writeAsStringSync('int main(void) { return 0; }\n');
    Future<String> compile(String name, List<String> arches) async {
      final output = '${root.path}/$name';
      final result = await Process.run('xcrun', [
        'clang',
        for (final arch in arches) ...['-arch', arch],
        source.path,
        '-o',
        output,
      ]);
      expect(result.exitCode, 0, reason: '${result.stderr}');
      return output;
    }

    // 直接调用发布脚本中的校验函数，使用本机真实 lipo（Xcode 27 不接受一次多个架构）。
    Future<ProcessResult> verify(String binary) => Process.run('python3', [
      '-c',
      'import sys; sys.path.insert(0, "."); '
          'from tools.release.prepare import verify_universal; '
          'verify_universal(sys.argv[1])',
      binary,
    ]);
    final universal = await compile('universal', ['x86_64', 'arm64']);
    final passed = await verify(universal);
    expect(passed.exitCode, 0, reason: '${passed.stderr}');
    final thin = await compile('arm64 only', ['arm64']);
    final failed = await verify(thin);
    expect(failed.exitCode, isNot(0));
    expect(failed.stderr, contains('missing architecture x86_64'));
  }, skip: !Platform.isMacOS);

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
    final names = [
      'Remlark-1.2.3-macos-universal.dmg',
      'Remlark-macos.zip',
      'Remlark-1.2.3-windows-x64-setup.exe',
      'Remlark-windows-x64.zip',
    ];
    for (final arch in ['x64', 'arm64']) {
      names.addAll([
        'Remlark-1.2.3-linux-${arch == 'x64' ? 'amd64' : 'arm64'}.deb',
        'Remlark-linux-$arch.tar.gz',
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
    expect(incomplete.stderr, contains('Remlark-sync-server-'));
    expect(File('${dist.path}/SHA256SUMS').existsSync(), isFalse);
    for (final platform in ['macos', 'windows', 'linux']) {
      for (final arch in ['x64', 'arm64']) {
        final extension = platform == 'windows' ? 'zip' : 'tar.gz';
        final name = 'Remlark-sync-server-1.2.3-$platform-$arch.$extension';
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
    expect(lines.length, 14);
    // Windows ARM64 桌面包不再是必需附件；服务端 windows-arm64 仍保留。
    final listed = lines.join('\n');
    expect(listed, isNot(contains('Remlark-1.2.3-windows-arm64-setup.exe')));
    expect(listed, isNot(contains('Remlark-windows-arm64.zip')));
    expect(listed, contains('Remlark-sync-server-1.2.3-windows-arm64.zip'));
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
