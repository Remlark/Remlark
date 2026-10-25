// 启动外部进程，ARM runner 上进程启动慢，放宽默认 30 秒时限。
@Timeout(Duration(minutes: 3))
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import '../utils/windows_powershell.dart';

/// 多平台测试 P-08：分平台打包入口与 Windows 安装包完整性、参数传递及失败处理。
void main() {
  test('三个平台保留独立打包入口，Windows 安装器支持中英文、当前用户安装与保留数据', () {
    final makefile = File('Makefile').readAsStringSync();
    for (final target in ['mac:', 'linux:', 'windows:', 'run:']) {
      expect(makefile, contains(target));
    }
    expect(makefile, contains('windows/packaging/build.ps1'));
    final installer = File('windows/packaging/remlark.iss').readAsStringSync();
    expect(installer, contains('PrivilegesRequired=lowest'));
    expect(
      installer,
      contains(r'DefaultDirName={localappdata}\Programs\Remlark'),
    );
    expect(installer, contains('ArchitecturesAllowed=x64compatible'));
    // 不再打包 Windows ARM64：安装器无 arm64 分支，打包脚本只接受 x64，Makefile 在 ARM64 主机停止。
    expect(installer, isNot(contains('ArchitecturesAllowed=arm64')));
    final packaging = File('windows/packaging/build.ps1').readAsStringSync();
    expect(packaging, contains("[ValidateSet('x64')]"));
    expect(makefile, contains('-Arch x64'));
    expect(makefile, contains('ifeq (\$(PROCESSOR_ARCHITECTURE),ARM64)'));
    expect(installer, contains('compiler:Default.isl'));
    expect(installer, contains(r'languages\ChineseSimplified.isl'));
    expect(installer, isNot(contains('[UninstallDelete]')));
    expect(File('windows/packaging/languages/LICENSE').existsSync(), isTrue);
    expect(File('windows/packaging/build.ps1').readAsBytesSync().take(3), [
      0xef,
      0xbb,
      0xbf,
    ]);
  });

  test('Windows 开发运行入口无须 Make，保留按需构建与显式重编译方式', () {
    final run = File('windows/run.ps1');
    expect(run.readAsBytesSync().take(3), [0xef, 0xbb, 0xbf]);
    final script = run.readAsStringSync();
    expect(
      script,
      contains(
        r'Invoke-BuildCommand python3 "$Root\tools\utils\app_version.py" flutter run -d windows',
      ),
    );
    expect(script, contains(r'$RebuildNative'));
    expect(script, contains(r'$PrepareOnly'));
    expect(script, contains('Launch-VsDevShell.ps1'));
    expect(script, isNot(contains('Invoke-BuildCommand make')));
  });

  if (!Platform.isWindows) return; // 安装器的暂存与命令执行只适用于 Windows，三平台入口已在上面检查。

  test('Windows PowerShell 可以解析开发启动脚本', () async {
    final result = await Process.run('powershell', [
      '-NoProfile',
      '-Command',
      '\$tokens = \$null; \$errors = \$null; '
          '[System.Management.Automation.Language.Parser]::ParseFile('
          "'windows/run.ps1', [ref]\$tokens, [ref]\$errors) | Out-Null; "
          'if (\$errors.Count) { \$errors | Out-String | Write-Output; exit 1 }',
    ], environment: windowsPowerShellEnvironment());
    expect(result.exitCode, 0, reason: '${result.stdout}\n${result.stderr}');
  });

  late Directory root;
  late Directory release;
  late Directory runtime;
  const payload = [
    'Remlark.exe',
    'flutter_windows.dll',
    'remlark_rdp.dll',
    'remlark_crypto.dll',
    'sqlite3.dll',
    'data/app.so',
    'data/icudtl.dat',
  ];
  const crt = ['msvcp140.dll', 'vcruntime140.dll', 'vcruntime140_1.dll'];

  /// 准备隔离的分发夹具，路径含空格和中文以覆盖 PowerShell 参数引用。
  setUp(() {
    root = Directory.systemTemp.createTempSync('rmk install 中文 ');
    release = Directory(p.join(root.path, 'Release'))..createSync();
    runtime = Directory(p.join(root.path, 'CRT'))..createSync();
    for (final name in payload) {
      final file = File(p.join(release.path, name));
      file.parent.createSync(recursive: true);
      file.writeAsStringSync('release-$name');
    }
    Directory(p.join(release.path, 'data', 'flutter_assets')).createSync();
    for (final name in crt) {
      File(p.join(runtime.path, name)).writeAsStringSync('runtime-$name');
    }
  });

  /// 清理本测试生成的临时文件，不修改项目产物。
  tearDown(() => root.deleteSync(recursive: true));

  /// 通过实际 Windows PowerShell 调用打包入口。
  Future<ProcessResult> runPackaging(List<String> extra) =>
      Process.run('powershell', [
        '-NoProfile',
        '-ExecutionPolicy',
        'Bypass',
        '-File',
        'windows/packaging/build.ps1',
        '-ReleaseDir',
        release.path,
        '-RuntimeDir',
        runtime.path,
        '-OutputDir',
        p.join(root.path, 'output'),
        ...extra,
      ], environment: windowsPowerShellEnvironment());

  test('暂存完整应用与 VC++ 运行库，原始 Release 保持完整', () async {
    final result = await runPackaging(['-StageOnly', '-Arch', 'arm64']);
    expect(result.exitCode, 0, reason: '${result.stdout}\n${result.stderr}');
    final stage = Directory((result.stdout as String).trim());
    addTearDown(() => stage.deleteSync(recursive: true));
    for (final name in [...payload, ...crt]) {
      expect(File(p.join(stage.path, name)).existsSync(), isTrue, reason: name);
    }
    expect(File(p.join(release.path, 'msvcp140.dll')).existsSync(), isFalse);
    expect(File(p.join(release.path, 'data/app.so')).existsSync(), isTrue);
  });

  test('ARM64 不要求 x64 专用运行库，x64 必须包含 FH4 运行库', () async {
    File(p.join(runtime.path, 'vcruntime140_1.dll')).deleteSync();
    final arm = await runPackaging(['-StageOnly', '-Arch', 'arm64']);
    expect(arm.exitCode, 0, reason: '${arm.stdout}${arm.stderr}');
    final stage = Directory((arm.stdout as String).trim());
    addTearDown(() => stage.deleteSync(recursive: true));
    final x64 = await runPackaging(['-StageOnly', '-Arch', 'x64']);
    expect(x64.exitCode, isNot(0));
    expect(x64.stderr, contains('vcruntime140_1.dll'));
  });

  test('从当前工具链查找 VS 2026 CRT，避免写死 VC143', () async {
    final redist = Directory(
      p.join(root.path, 'redist', 'arm64', 'Microsoft.VC145.CRT'),
    )..createSync(recursive: true);
    for (final name in ['msvcp140.dll', 'vcruntime140.dll']) {
      File(p.join(redist.path, name)).writeAsStringSync('arm-runtime');
    }
    final result = await Process.run(
      'powershell',
      [
        '-NoProfile',
        '-ExecutionPolicy',
        'Bypass',
        '-File',
        'windows/packaging/build.ps1',
        '-StageOnly',
        '-Arch',
        'arm64',
        '-ReleaseDir',
        release.path,
      ],
      environment: windowsPowerShellEnvironment({
        'VCToolsRedistDir': p.join(root.path, 'redist'),
        'VC_REDIST_DIR': '',
      }),
    );
    expect(result.exitCode, 0, reason: '${result.stdout}${result.stderr}');
    final stage = Directory((result.stdout as String).trim());
    addTearDown(() => stage.deleteSync(recursive: true));
    expect(
      File(p.join(stage.path, 'msvcp140.dll')).readAsStringSync(),
      'arm-runtime',
    );
  });

  test('缺少原生库或 VC++ 运行库时阻止生成不完整安装包', () async {
    final rdp = File(p.join(release.path, 'remlark_rdp.dll'));
    rdp.deleteSync();
    var result = await runPackaging(['-StageOnly']);
    expect(result.exitCode, isNot(0));
    expect(result.stderr, contains('remlark_rdp.dll'));
    rdp.writeAsStringSync('rdp');
    File(p.join(runtime.path, 'vcruntime140.dll')).deleteSync();
    result = await runPackaging(['-StageOnly']);
    expect(result.exitCode, isNot(0));
    expect(result.stderr, contains('vcruntime140.dll'));
  });

  test('Windows 拒绝将与 VERSION 不符的旧 exe 按新版本打包', () async {
    // 夹具 exe 没有目标资源版本，必须在调用安装器编译器之前被拒绝。
    final compiler = File(p.join(root.path, 'fake compiler.cmd'))
      ..writeAsStringSync('@echo off\r\nexit /b 99\r\n');
    final result = await runPackaging(['-CompilerPath', compiler.path]);
    expect(result.exitCode, isNot(0));
    expect(result.stderr, contains('Release version does not match VERSION'));
  });
}
