import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// 多平台测试 P-25：发布前仅运行平台专项，覆盖五路（Windows 仅 x64）且不构建或发布应用。
void main() {
  final workflow = File('.github/workflows/test.yml')
      .readAsLinesSync()
      .join('\n');

  test('test 前缀标签触发独立测试，五路平台均保留失败结果', () {
    expect(workflow, contains("tags: ['test*']"));
    expect(workflow, contains('workflow_dispatch:'));
    expect(workflow, contains('fail-fast: false'));
    for (final entry in [
      'linux, arch: x64, runner: ubuntu-24.04',
      'linux, arch: arm64, runner: ubuntu-24.04-arm',
      'windows, arch: x64, runner: windows-2022',
      'macos, arch: x64, runner: macos-15-intel',
      'macos, arch: arm64, runner: macos-15',
    ]) {
      expect(workflow, contains('platform: $entry }'));
    }
    // 不再支持 Windows ARM64 桌面端，平台专项不再运行该路。
    expect(workflow, isNot(contains('windows-11-arm')));
    // v 标签仍由独立发布工作流处理。
    expect(
      File('.github/workflows/release.yml').readAsStringSync(),
      contains("tags: ['v*']"),
    );
  });

  test('仅执行一次平台专项，不安装服务端依赖或运行其他测试套件', () {
    expect(workflow, contains('run: make test-platform'));
    expect('run: make test-platform'.allMatches(workflow).length, 1);
    expect(workflow, contains('flutter pub get --enforce-lockfile'));
    // 防止后续加入高成本测试或无关服务依赖，保持测试标签快速反馈。
    for (final command in [
      'flutter test',
      'dart test',
      'dart pub get',
      'working-directory: server',
      'RMK_DSH_E2E',
      'openssh-server',
    ]) {
      expect(workflow, isNot(contains(command)), reason: command);
    }
  });

  test('仅精确恢复原生缓存，缺失时明确报告覆盖范围', () {
    expect(workflow, contains('uses: actions/cache/restore@v4'));
    expect(
      workflow,
      contains(
        "key: native-v2-\u0024{{ matrix.runner }}-"
        "\u0024{{ matrix.platform == 'macos' && matrix.arch == 'arm64' && 'universal' || matrix.arch }}-"
        "\u0024{{ steps.native-identity.outputs.identity }}-"
        "\u0024{{ hashFiles('native/**') }}",
      ),
    );
    expect(workflow, isNot(contains('restore-keys:')));
    expect(workflow, contains('No matching native cache.'));
    expect(workflow, contains('GITHUB_STEP_SUMMARY'));
    expect(workflow, contains('RMK_REQUIRE_RDP_NATIVE:'));
  });

  test('不构建应用、安装包或原生依赖，不上传产物或发布', () {
    // 测试运行时仍会编译 Dart 与小型 C 夹具；禁止耗时的产品构建入口。
    for (final command in [
      'flutter build',
      'dart build',
      'make mac',
      'make linux',
      'make windows',
      'make native-lib',
      'make rdp-test-server',
      'actions/upload-artifact',
      'actions/cache/save',
      'gh release',
      'secrets.',
      'contents: write',
    ]) {
      expect(workflow, isNot(contains(command)), reason: command);
    }
  });
}
