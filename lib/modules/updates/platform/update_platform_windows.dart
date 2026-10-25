import 'dart:convert';
import 'dart:ffi';
import 'dart:io';

import 'package:path/path.dart' as p;

import '../../../utils/script_utils.dart';
import '../install/install_helpers.dart';
import '../install/install_plan.dart';
import '../update_release.dart';
import 'update_platform.dart';

/// Windows 使用原有 Inno Setup，以无人值守参数安装到当前目录后重启。
class WindowsUpdatePlatform implements UpdatePlatform {
  WindowsUpdatePlatform(this.abi);
  final Abi abi;

  /// setup 按 ABI 选择，便携用户点击升级后也安装到当前目录。
  @override
  String? assetName(String version) => switch (abi) {
    Abi.windowsX64 => 'Remlark-$version-windows-x64-setup.exe',
    Abi.windowsArm64 => 'Remlark-$version-windows-arm64-setup.exe',
    _ => null,
  };

  /// 路径通过 JSON 传递给 PowerShell，准备独立助手并按目录权限决定是否请求 UAC。
  @override
  Future<InstallPlan> prepare(InstallContext context) async {
    final target = p.dirname(context.executable);
    InstallHelpers.validateTarget(target);
    if (p.basename(context.executable).toLowerCase() != 'remlark.exe') {
      throw const UpdateFailure('updates.error.location');
    }
    final backup =
        '$target.remlark-backup-${p.basename(context.directory.path)}';
    await File(p.join(context.directory.path, 'backup')).writeAsString(backup);
    await File(p.join(context.directory.path, 'install.json')).writeAsString(
      jsonEncode({
        'target': target,
        'backup': backup,
        'archive': context.archive.path,
        'executable': context.executable,
        'processId': context.processId,
        'elevate':
            !await InstallHelpers.writable(target) ||
            !await InstallHelpers.writable(p.dirname(target)),
      }),
    );
    final worker = File(p.join(context.directory.path, 'worker.ps1'));
    // PowerShell 5.1 通过 BOM 识别 UTF-8，否则中文注释可能破坏脚本解析。
    await ScriptUtils.write(worker, workerScript, withBom: true);
    final launcher = File(p.join(context.directory.path, 'launch.ps1'));
    await ScriptUtils.write(launcher, launcherScript, withBom: true);
    return InstallPlan(
      executable: 'powershell.exe',
      arguments: [
        '-NoProfile',
        '-NonInteractive',
        '-ExecutionPolicy',
        'Bypass',
        '-File',
        launcher.path,
      ],
      directory: context.directory,
    );
  }

  /// 工作脚本在退出后备份完整应用，安装器失败时恢复旧目录。
  static const workerScript = r'''
$ErrorActionPreference = 'Stop'
Set-Location -LiteralPath $PSScriptRoot
$c = Get-Content -LiteralPath (Join-Path $PSScriptRoot 'install.json') -Raw -Encoding UTF8 | ConvertFrom-Json
$backupComplete = $false
try {
  Set-Content -LiteralPath 'ready' -Value 'ready'
  $deadline = (Get-Date).AddSeconds(120)
  while (Get-Process -Id $c.processId -ErrorAction SilentlyContinue) {
    if ((Get-Date) -gt $deadline) { throw 'exit timeout' }
    Start-Sleep -Milliseconds 250
  }
  if (!(Test-Path -LiteralPath 'commit') -or (Test-Path -LiteralPath 'abort')) { throw 'not authorized' }
  Copy-Item -LiteralPath $c.target -Destination $c.backup -Recurse
  $backupComplete = $true
  $installerArguments = @('/VERYSILENT', '/SUPPRESSMSGBOXES', '/SP-', '/NORESTART', '/NOCLOSEAPPLICATIONS', '/NORESTARTAPPLICATIONS', ('/DIR="' + $c.target + '"'))
  $setup = Start-Process -FilePath $c.archive -ArgumentList $installerArguments -Wait -PassThru
  if ($setup.ExitCode -ne 0) { throw 'installer failed' }
  Set-Content -LiteralPath 'result' -Value 'success'
} catch {
  # 安装器失败时恢复程序文件；不触碰应用数据目录。
  if ($backupComplete -and (Test-Path -LiteralPath $c.backup) -and !(Get-Process -Id $c.processId -ErrorAction SilentlyContinue)) {
    $failed = $c.backup + '.failed'
    try {
      Move-Item -LiteralPath $c.target -Destination $failed
      Move-Item -LiteralPath $c.backup -Destination $c.target
      Remove-Item -LiteralPath $failed -Recurse -Force
    } catch {}
  }
  Set-Content -LiteralPath 'result' -Value 'failed'
  exit 1
}
''';

  /// 监督进程保持用户身份，UAC 只授予安装助手，应用重启不继承管理员权限。
  static const launcherScript = r'''
$ErrorActionPreference = 'Stop'
Set-Location -LiteralPath $PSScriptRoot
$c = Get-Content -LiteralPath 'install.json' -Raw -Encoding UTF8 | ConvertFrom-Json
try {
  $worker = Join-Path $PSScriptRoot 'worker.ps1'
  $workerArguments = @('-NoProfile', '-NonInteractive', '-ExecutionPolicy', 'Bypass', '-File', ('"' + $worker + '"'))
  if ($c.elevate) {
    Start-Process -FilePath 'powershell.exe' -ArgumentList $workerArguments -Verb RunAs -Wait | Out-Null
  } else {
    Start-Process -FilePath 'powershell.exe' -ArgumentList $workerArguments -WindowStyle Hidden -Wait | Out-Null
  }
} catch {}
if (!(Test-Path -LiteralPath 'result')) { Set-Content -LiteralPath 'result' -Value 'failed' }
if (!(Get-Process -Id $c.processId -ErrorAction SilentlyContinue)) {
  Start-Process -FilePath $c.executable -WorkingDirectory $c.target
}
''';
}
