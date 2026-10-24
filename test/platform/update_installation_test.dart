import 'dart:ffi';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:remlark/modules/updates/install/install_helpers.dart';
import 'package:remlark/modules/updates/install/install_plan.dart';
import 'package:remlark/modules/updates/platform/update_platform_macos.dart';
import 'package:remlark/modules/updates/platform/update_platform_linux.dart';
import 'package:remlark/modules/updates/platform/update_platform_windows.dart';
import 'package:remlark/modules/updates/update_release.dart';
import 'package:remlark/utils/git_credentials/git_credentials.dart';
import 'package:remlark/utils/platform_utils.dart';
import 'package:remlark/utils/shell_utils.dart';

/// 在隔离目录运行真正的安装工作脚本，不接触已安装应用、真实凭据或系统授权。
void main() {
  late Directory root;
  setUp(() async {
    root = await Directory.systemTemp.createTemp('remlark-upgrade-test-');
  });
  tearDown(() async {
    if (await root.exists()) await root.delete(recursive: true);
  });

  test('P-19 Windows 两种架构生成带 BOM 的助手，PowerShell 5.1 可以解析', () async {
    final target = await Directory(p.join(root.path, '安装目录')).create();
    for (final abi in [Abi.windowsX64, Abi.windowsArm64]) {
      final stage = await Directory(p.join(root.path, '$abi')).create();
      await WindowsUpdatePlatform(abi).prepare(
        InstallContext(
          directory: stage,
          archive: File(p.join(root.path, 'installer.exe')),
          version: '1.2.0',
          executable: p.join(target.path, 'remlark.exe'),
          processId: 2147483647,
        ),
      );
      for (final name in ['worker.ps1', 'launch.ps1']) {
        final script = File(p.join(stage.path, name));
        expect((await script.readAsBytes()).take(3), [0xef, 0xbb, 0xbf]);
        if (Platform.isWindows) {
          // 只解析真实生成文件，不启动安装或监督进程。
          final parsed = await Process.run(
            'powershell.exe',
            [
              '-NoProfile',
              '-NonInteractive',
              '-Command',
              r'$tokens=$null; $errors=$null; '
                  r'[void][System.Management.Automation.Language.Parser]::ParseFile('
                  r'$env:RMK_TEST_SCRIPT,[ref]$tokens,[ref]$errors); '
                  r'if ($errors.Count) { $errors | Out-String | Write-Error; exit 1 }',
            ],
            environment: {'RMK_TEST_SCRIPT': script.path},
          );
          expect(parsed.exitCode, 0, reason: '${parsed.stderr}');
        }
      }
    }
  });

  test('P-19 macOS 与 Linux 共用助手保持无 BOM 的 UTF-8 和 shebang', () async {
    final context = InstallContext(
      directory: root,
      archive: File('unused'),
      version: '1.2.0',
      executable: '/unused',
      processId: 2147483647,
    );
    await InstallHelpers.posixPlan(
      context,
      InstallHelpers.posixWorker(context, 'printf success > result'),
      invocation: '/bin/sh worker.sh',
      relaunch: ':',
    );
    for (final name in ['worker.sh', 'launch.sh']) {
      final script = File(p.join(root.path, name));
      expect((await script.readAsBytes()).take(2), [0x23, 0x21]);
      expect(await script.readAsString(), contains('退出'));
    }
  });

  test('P-19 Git 凭据只接受 GitHub HTTPS，密码不会进入持久化配置', () {
    expect(
      GitCredentials.parse(
        'protocol=https\nhost=github.com\nusername=test\npassword=example-secret\n',
      ),
      'example-secret',
    );
    expect(
      GitCredentials.parse(
        'protocol=https\nhost=evil.example\npassword=secret\n',
      ),
      isNull,
    );
    expect(
      GitCredentials.parse('protocol=ssh\nhost=github.com\npassword=secret\n'),
      isNull,
    );
    expect(
      GitCredentials.parse(
        'protocol=https\nhost=github.com\npassword=bad secret\n',
      ),
      isNull,
    );
  });

  test('P-19 实际 Git credential fill 读取隔离仓库 helper，未配置时不交互', () async {
    final git = PlatformUtils.which('git');
    if (git == null) return;
    final config = File(p.join(root.path, 'empty-config'));
    await config.writeAsString('');
    final environment = {
      'GIT_CONFIG_NOSYSTEM': '1',
      'GIT_CONFIG_GLOBAL': config.path,
    };
    final init = await Process.run(git, [
      'init',
      root.path,
    ], environment: environment);
    expect(init.exitCode, 0);
    final store = File(p.join(root.path, 'credentials'));
    await store.writeAsString(
      'https://fixture:fixture-only-secret@github.com\n',
    );
    final helperPath = store.path.replaceAll(r'\', '/');
    await Process.run(git, [
      '-C',
      root.path,
      'config',
      'credential.helper',
      'store --file=${ShellUtils.quote(helperPath)}',
    ], environment: environment);
    final credentials = GitCredentials(
      workingDirectory: root.path,
      environment: environment,
    );
    expect(await credentials.githubToken(), 'fixture-only-secret');
    await store.writeAsString('');
    expect(await credentials.githubToken(), isNull);
  });

  test('P-19 POSIX 工作脚本未经提交不能修改安装，提交后正确替换含特殊字符路径', () async {
    final target = await Directory(p.join(root.path, "安装 ' \$() 目录")).create();
    final source = await Directory(p.join(root.path, 'source')).create();
    await File(p.join(target.path, 'version')).writeAsString('old');
    await File(p.join(source.path, 'version')).writeAsString('new');
    final context = InstallContext(
      directory: root,
      archive: File('unused'),
      version: '1.2.0',
      executable: '/unused',
      processId: 2147483647,
    );
    final body = InstallHelpers.posixReplace(
      source: source.path,
      target: target.path,
      copyCommand: '/bin/cp -a',
      suffix: 'test',
    );
    final script = File(p.join(root.path, 'worker.sh'));
    await script.writeAsString(InstallHelpers.posixWorker(context, body));
    final rejected = await Process.run('/bin/sh', [script.path]);
    expect(rejected.exitCode, isNot(0));
    expect(await File(p.join(target.path, 'version')).readAsString(), 'old');
    await File(p.join(root.path, 'commit')).writeAsString('commit');
    final installed = await Process.run('/bin/sh', [script.path]);
    expect(installed.exitCode, 0, reason: '${installed.stderr}');
    expect(await File(p.join(target.path, 'version')).readAsString(), 'new');
    expect(
      await File('${target.path}.remlark-backup-test/version').readAsString(),
      'old',
    );
  }, skip: Platform.isWindows);

  test('P-19 POSIX 提交阶段失败自动恢复旧目录', () async {
    final target = await Directory(p.join(root.path, 'app')).create();
    final source = await Directory(p.join(root.path, 'source')).create();
    await File(p.join(target.path, 'version')).writeAsString('old');
    await File(p.join(source.path, 'version')).writeAsString('new');
    final bin = await Directory(p.join(root.path, 'bin')).create();
    final mv = File(p.join(bin.path, 'mv'));
    await mv.writeAsString(r'''#!/bin/sh
n=0
if [ -f "$RMK_TEST_COUNTER" ]; then n=$(cat "$RMK_TEST_COUNTER"); fi
n=$((n + 1))
printf '%s' "$n" > "$RMK_TEST_COUNTER"
if [ "$n" = 2 ]; then exit 2; fi
exec /bin/mv "$@"
''');
    await Process.run('chmod', ['+x', mv.path]);
    final context = InstallContext(
      directory: root,
      archive: File('unused'),
      version: '1.2.0',
      executable: '/unused',
      processId: 2147483647,
    );
    final script = File(p.join(root.path, 'worker.sh'));
    await script.writeAsString(
      InstallHelpers.posixWorker(
        context,
        InstallHelpers.posixReplace(
          source: source.path,
          target: target.path,
          copyCommand: '/bin/cp -a',
          suffix: 'test',
        ),
      ),
    );
    await File(p.join(root.path, 'commit')).writeAsString('commit');
    final result = await Process.run(
      '/bin/sh',
      [script.path],
      environment: {
        'PATH': '${bin.path}:/usr/bin:/bin',
        'RMK_TEST_COUNTER': p.join(root.path, 'counter'),
      },
    );
    expect(result.exitCode, isNot(0));
    expect(await File(p.join(target.path, 'version')).readAsString(), 'old');
    expect(await File(p.join(root.path, 'result')).readAsString(), 'failed');
  }, skip: Platform.isWindows);

  test('P-19 POSIX 助手等待原进程退出，退出前不修改文件', () async {
    final target = await Directory(p.join(root.path, 'app')).create();
    final source = await Directory(p.join(root.path, 'source')).create();
    await File(p.join(target.path, 'version')).writeAsString('old');
    await File(p.join(source.path, 'version')).writeAsString('new');
    final parent = await Process.start('/bin/sleep', ['30']);
    addTearDown(() {
      parent.kill();
    });
    final context = InstallContext(
      directory: root,
      archive: File('unused'),
      version: '1.2.0',
      executable: '/unused',
      processId: parent.pid,
    );
    final script = File(p.join(root.path, 'worker.sh'));
    await script.writeAsString(
      InstallHelpers.posixWorker(
        context,
        InstallHelpers.posixReplace(
          source: source.path,
          target: target.path,
          copyCommand: '/bin/cp -a',
          suffix: 'test',
        ),
      ),
    );
    await File(p.join(root.path, 'commit')).writeAsString('commit');
    final worker = await Process.start('/bin/sh', [script.path]);
    addTearDown(() {
      worker.kill();
    });
    final stdout = worker.stdout.drain<void>();
    final stderr = worker.stderr.drain<void>();
    final deadline = DateTime.now().add(const Duration(seconds: 5));
    while (!await File(p.join(root.path, 'ready')).exists() &&
        DateTime.now().isBefore(deadline)) {
      await Future<void>.delayed(const Duration(milliseconds: 20));
    }
    expect(await File(p.join(target.path, 'version')).readAsString(), 'old');
    parent.kill();
    await parent.exitCode;
    expect(await worker.exitCode.timeout(const Duration(seconds: 5)), 0);
    await stdout;
    await stderr;
    expect(await File(p.join(target.path, 'version')).readAsString(), 'new');
  }, skip: Platform.isWindows);

  test('P-19 macOS 真正验证 zip 签名/版本，工作脚本替换隔离 App', () async {
    final source = await Directory(
      p.join(root.path, 'source/remlark.app/Contents/MacOS'),
    ).create(recursive: true);
    final bundle = p.dirname(p.dirname(source.path));
    await File('/bin/echo').copy(p.join(source.path, 'remlark'));
    await File(p.join(bundle, 'Contents/Info.plist')).writeAsString(
      '''<?xml version="1.0"?><plist version="1.0"><dict><key>CFBundleIdentifier</key><string>com.remlark.upgrade-test</string><key>CFBundleExecutable</key><string>remlark</string><key>CFBundlePackageType</key><string>APPL</string><key>CFBundleShortVersionString</key><string>1.2.0</string></dict></plist>''',
    );
    await InstallHelpers.run('/usr/bin/codesign', [
      '--force',
      '--sign',
      '-',
      bundle,
    ]);
    final archive = File(p.join(root.path, 'package.zip'));
    await InstallHelpers.run('/usr/bin/ditto', [
      '-c',
      '-k',
      '--keepParent',
      bundle,
      archive.path,
    ]);
    final stage = await Directory(p.join(root.path, 'stage')).create();
    final target = await Directory(
      p.join(root.path, 'Installed.app/Contents/MacOS'),
    ).create(recursive: true);
    final executable = p.join(target.path, 'remlark');
    await File(executable).writeAsString('old');
    final plan = await MacosUpdatePlatform(Abi.macosX64).prepare(
      InstallContext(
        directory: stage,
        archive: archive,
        version: '1.2.0',
        executable: executable,
        processId: 2147483647,
      ),
    );
    await File(p.join(stage.path, 'commit')).writeAsString('commit');
    final result = await Process.run('/bin/sh', [
      p.join(stage.path, 'worker.sh'),
    ]);
    expect(result.exitCode, 0, reason: '${result.stderr}');
    expect(await File(executable).length(), greaterThan(3));
    expect(plan.executable, '/bin/sh');
    final wrongStage = await Directory(p.join(root.path, 'wrong')).create();
    await expectLater(
      MacosUpdatePlatform(Abi.macosX64).prepare(
        InstallContext(
          directory: wrongStage,
          archive: archive,
          version: '9.0.0',
          executable: executable,
          processId: 2147483647,
        ),
      ),
      throwsA(isA<UpdateFailure>()),
    );
  }, skip: !Platform.isMacOS);

  test('P-19 Linux 真实解压便携包并原位替换隔离 bundle', () async {
    final bundle = await Directory(p.join(root.path, 'source/bundle'))
        .create(recursive: true);
    for (final directory in ['lib', 'data']) {
      await Directory(p.join(bundle.path, directory)).create();
    }
    await File(p.join(bundle.path, 'remlark')).writeAsString('new');
    final target = await Directory(p.join(root.path, 'installed')).create();
    for (final directory in ['lib', 'data']) {
      await Directory(p.join(target.path, directory)).create();
    }
    final executable = p.join(target.path, 'remlark');
    await File(executable).writeAsString('old');
    final archive = File(p.join(root.path, 'package.tar.gz'));
    await InstallHelpers.run('tar', [
      '-czf',
      archive.path,
      '-C',
      p.dirname(bundle.path),
      'bundle',
    ]);
    final stage = await Directory(p.join(root.path, 'stage')).create();
    await LinuxUpdatePlatform(Abi.linuxX64).prepare(
      InstallContext(
        directory: stage,
        archive: archive,
        version: '1.2.0',
        executable: executable,
        processId: 2147483647,
      ),
    );
    await File(p.join(stage.path, 'commit')).writeAsString('commit');
    final result = await Process.run('/bin/sh', [
      p.join(stage.path, 'worker.sh'),
    ]);
    expect(result.exitCode, 0, reason: '${result.stderr}');
    expect(await File(executable).readAsString(), 'new');
  }, skip: Platform.isWindows);

  for (final fail in [false, true]) {
    test('P-19 Windows 实际执行安装助手，安装失败回滚=$fail', () async {
      final target = await Directory(p.join(root.path, 'app')).create();
      final executable = p.join(target.path, 'remlark.exe');
      await File(executable).writeAsString('placeholder');
      await File(p.join(target.path, 'version')).writeAsString('old');
      final archive = File(p.join(root.path, 'installer.cmd'));
      await archive.writeAsString(
        '@echo off\r\necho attempted>"%~dp0installer-ran"\r\n'
        'echo new>"%~dp0app\\version"\r\nexit /b ${fail ? 1 : 0}\r\n',
      );
      final stage = await Directory(p.join(root.path, 'stage')).create();
      await WindowsUpdatePlatform(Abi.windowsX64).prepare(
        InstallContext(
          directory: stage,
          archive: archive,
          version: '1.2.0',
          executable: executable,
          processId: 2147483647,
        ),
      );
      await File(p.join(stage.path, 'commit')).writeAsString('commit');
      final result = await Process.run('powershell.exe', [
        '-NoProfile',
        '-NonInteractive',
        '-ExecutionPolicy',
        'Bypass',
        '-File',
        p.join(stage.path, 'worker.ps1'),
      ]);
      expect(result.exitCode, fail ? 1 : 0, reason: '${result.stderr}');
      // 验证脚本确实执行到安装结果，避免语法错误的退出码 1 被误认为回滚成功。
      expect(
        (await File(p.join(stage.path, 'result')).readAsString()).trim(),
        fail ? 'failed' : 'success',
      );
      expect(await File(p.join(stage.path, 'ready')).exists(), isTrue);
      expect(
        (await File(p.join(root.path, 'installer-ran')).readAsString()).trim(),
        'attempted',
      );
      expect(
        (await File(p.join(target.path, 'version')).readAsString()).trim(),
        fail ? 'old' : 'new',
      );
    }, skip: !Platform.isWindows);
  }
}
