# Windows 开发启动入口，不依赖 GNU Make；已有原生库时可直接使用普通 PowerShell。
param(
  [switch]$RebuildNative,
  [switch]$PrepareOnly
)
$ErrorActionPreference = 'Stop'
$Root = (Resolve-Path "$PSScriptRoot\..").Path
. "$Root\native\utils\windows_build.ps1"
if (-not (Get-Command flutter -ErrorAction SilentlyContinue)) {
  throw 'Flutter not found. Add the Flutter SDK bin directory to PATH.'
}

Push-Location $Root
try {
  Invoke-BuildCommand flutter pub get
  $nativeDir = Join-Path $Root 'build\native\windows-x86_64'
  $needsNative = $RebuildNative -or
    -not (Test-Path -LiteralPath "$nativeDir\remlark_rdp.dll") -or
    -not (Test-Path -LiteralPath "$nativeDir\remlark_crypto.dll")
  if ($needsNative) {
    # 原生编译需要 MSVC 的环境变量；普通终端中通过 VS 官方入口初始化 x64 环境。
    if (-not (Get-Command cl.exe -ErrorAction SilentlyContinue)) {
      $vswhere = Join-Path ${env:ProgramFiles(x86)} 'Microsoft Visual Studio\Installer\vswhere.exe'
      if (-not (Test-Path -LiteralPath $vswhere)) { throw 'Install Visual Studio 2022 with Desktop development with C++.' }
      $vsPath = & $vswhere -latest -products '*' -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath
      if ($LASTEXITCODE -ne 0 -or -not $vsPath) { throw 'Visual Studio C++ tools not found.' }
      & "$vsPath\Common7\Tools\Launch-VsDevShell.ps1" -Arch amd64 -HostArch amd64 -SkipAutomaticLocation
    }
    # Perl / NASM 等工具需按编译环境文档加入 PATH；现有完整原生库可跳过首次构建。
    Invoke-BuildCommand powershell -NoProfile -ExecutionPolicy Bypass -File "$Root\native\rdp\scripts\build.ps1" -Arch x86_64
    Invoke-BuildCommand powershell -NoProfile -ExecutionPolicy Bypass -File "$Root\native\ssh_crypto\scripts\build.ps1" -Arch x86_64
  }
  if (-not $PrepareOnly) { Invoke-BuildCommand python3 "$Root\tools\utils\app_version.py" flutter run -d windows }
} finally {
  Pop-Location
}
