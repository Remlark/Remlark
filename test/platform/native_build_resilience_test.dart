import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// 提取缓存路径集合，确保 restore/save 使用同一缓存版本而非只匹配同名键。
String cachePaths(String workflow, String step) {
  final start = workflow.indexOf('- name: $step');
  expect(start, isNonNegative);
  final paths = RegExp(r'path: \|\r?\n((?:            [^\r\n]+\r?\n)+)')
      .firstMatch(workflow.substring(start));
  expect(paths, isNotNull);
  return paths!.group(1)!.split('\n').map((line) => line.trim()).join('\n');
}

/// 多平台测试 P-27：原生构建的前置检查、阶段完整性及失败后缓存恢复。
void main() {
  test('三平台阶段记录、安装残缺、缓存隔离与低成本预检查', () async {
    final result = await Process.run('python3', [
      'tools/testing/native_build_state_test.py',
      '-v',
    ]);
    expect(result.exitCode, 0, reason: '${result.stdout}\n${result.stderr}');
    expect('${result.stdout}${result.stderr}', contains('OK'));
  });

  test('工具链检查先于下载和编译，两个原生库均验证完整阶段', () {
    final windows = File('native/rdp/scripts/build.ps1').readAsStringSync();
    expect(
      windows.indexOf('Assert-ClTarget'),
      lessThan(windows.indexOf('function Fetch')),
    );
    expect(
      windows.indexOf('--check-toolchain'),
      lessThan(windows.indexOf('# 1. OpenSSL')),
    );
    expect(windows, contains('finally { Pop-Location }'));
    final posix = File('native/rdp/scripts/build.sh').readAsStringSync();
    expect(
      posix.indexOf('Missing native build tool'),
      lessThan(posix.indexOf('fetch()')),
    );
    for (final lib in ['rdp', 'ssh_crypto']) {
      for (final script in ['build.ps1', 'build.sh']) {
        final source = File('native/$lib/scripts/$script').readAsStringSync();
        expect(source, contains('native_build_state.py'));
        expect(source, contains('mark'));
        expect(source, contains('invalidate'));
      }
    }
    final workflow = File('.github/workflows/release.yml').readAsStringSync();
    expect(workflow, contains('native-progress-v1-'));
    expect(
      workflow,
      contains('steps.native-progress.outputs.cache-primary-key'),
    );
    expect(
      workflow,
      contains("steps.native-state.outputs.dependencies == 'true'"),
    );
    expect(workflow, contains("steps.native-state.outputs.complete == 'true'"));
    expect(workflow, contains("steps.native-state.outputs.complete != 'true'"));
    // 阶段进度绑定第三方配方、runner 和架构；胶水层代码改动不应使 OpenSSL 作废。
    final progress = workflow.substring(
      workflow.indexOf('      - name: Restore completed native stages'),
      workflow.indexOf('      - name: Flutter dependencies'),
    );
    expect(progress, contains("hashFiles('native/rdp/scripts/build.sh',"));
    expect(progress, isNot(contains("hashFiles('native/**')")));
    expect(progress, contains('build/native/*/prefix'));
    expect(progress, contains('build/native/*/.completed'));
    expect(progress, isNot(contains('build/native/*/openssl-build')));
    final paths = cachePaths(workflow, 'Restore native dependencies');
    expect(paths, cachePaths(workflow, 'Save complete native dependencies'));
    expect(
      paths,
      cachePaths(
        File('.github/workflows/test.yml').readAsStringSync(),
        'Restore matching native test dependencies',
      ),
    );
    expect(paths, contains('libremlark_*.*'));
    expect(paths, isNot(contains('shim-build')));
  });

  test('Windows 前置检查确认真实编译器目标并拒绝缺失工具', () async {
    if (!Platform.isWindows) return;
    final result = await Process.run('powershell', [
      '-NoProfile',
      '-ExecutionPolicy',
      'Bypass',
      '-File',
      'tools/testing/windows_build_checks.ps1',
    ]);
    expect(result.exitCode, 0, reason: '${result.stdout}\n${result.stderr}');
    expect(result.stdout, contains('Windows build wrapper checks passed'));
  });
}
