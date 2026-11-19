// 启动外部进程，ARM runner 上进程启动慢，放宽默认 30 秒时限。
@Timeout(Duration(minutes: 3))
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// 多平台测试 P-15：自签凭据保护、签名顺序与 macOS 真实签名。
void main() {
  test('签名失败保护在三平台执行，macOS 额外验证真实自签证书', () async {
    final result = await Process.run('python3', [
      'test/platform/fixtures/macos_signing_checks.py',
      '-v',
    ]);
    expect(result.exitCode, 0, reason: '${result.stdout}\n${result.stderr}');
  }, timeout: const Timeout(Duration(minutes: 2)));

  test('仅 macOS 导入证书，签名后重新打包，失败后也清理凭据', () {
    final workflow = File('.github/workflows/release.yml')
        .readAsLinesSync()
        .join('\n');
    final install = workflow.substring(
      workflow.indexOf('      - name: Import macOS signing certificate'),
      workflow.indexOf('      - name: macOS build dependencies'),
    );
    expect(install, contains("if: runner.os == 'macOS'"));
    for (final name in [
      'MACOS_CERTIFICATE_BASE64',
      'MACOS_CERTIFICATE_PASSWORD',
    ]) {
      expect(install, contains('secrets.$name'));
    }
    expect(workflow, isNot(contains('secrets.MACOS_SIGNING_IDENTITY')));
    expect(workflow, isNot(contains('secrets.MACOS_KEYCHAIN_PASSWORD')));
    final build = workflow.substring(
      workflow.indexOf('      - name: Build macOS universal installer'),
      workflow.indexOf('      # 原生库编译后'),
    );
    expect(build, contains("if: runner.os == 'macOS'"));
    expect(build.indexOf('make mac'), lessThan(build.indexOf('sign-app')));
    expect(
      build.indexOf('sign-app'),
      lessThan(build.indexOf('prepare.py macos')),
    );
    expect(
      build.indexOf('prepare.py macos'),
      lessThan(build.indexOf('sign-dmg')),
    );
    expect(build, contains("if: always() && runner.os == 'macOS'"));
    expect(build, contains('macos_signing.py cleanup'));
  });

  test('make run / make mac 先生成本地签名配置，Xcode 可选引入且默认临时签名', () {
    final makefile = File('Makefile').readAsStringSync();
    expect(makefile, contains('macos_signing.py xcode-config'));
    expect(
      RegExp(r'^mac: .*mac-signing', multiLine: true).hasMatch(makefile),
      isTrue,
    );
    expect(
      RegExp(r'^run: .*mac-signing', multiLine: true).hasMatch(makefile),
      isTrue,
    );
    final appInfo = File('macos/Runner/Configs/AppInfo.xcconfig')
        .readAsStringSync();
    expect(appInfo, contains('CODE_SIGN_STYLE = Automatic'));
    expect(appInfo, contains('#include? "Signing.local.xcconfig"'));
    expect(
      appInfo.indexOf('CODE_SIGN_STYLE'),
      lessThan(appInfo.indexOf('#include?')),
    );
    // Runner 目标的签名方式若写在工程文件里，会覆盖 xcconfig，本地身份无法生效。
    final project = File('macos/Runner.xcodeproj/project.pbxproj')
        .readAsStringSync();
    final runner = RegExp(
      r'baseConfigurationReference = \w+ /\* AppInfo\.xcconfig \*/;.*?\n\t\t\};',
      dotAll: true,
    ).allMatches(project).map((match) => match.group(0)!).toList();
    expect(runner, hasLength(3));
    for (final block in runner) {
      expect(block, isNot(contains('CODE_SIGN_STYLE')));
      expect(block, isNot(contains('CODE_SIGN_IDENTITY')));
    }
    expect(
      File('macos/.gitignore').readAsStringSync(),
      contains('Runner/Configs/Signing.local.xcconfig'),
    );
  });
}
