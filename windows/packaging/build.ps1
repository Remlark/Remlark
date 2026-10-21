# Windows x64 / arm64 分发：校验 Release，附带应用本地 VC++ 运行库，生成安装程序和便携包。
param(
  [ValidateSet('x64', 'arm64')] [string]$Arch = 'x64',
  [string]$ReleaseDir,
  [string]$OutputDir = 'dist',
  [string]$CompilerPath = $env:ISCC,
  [string]$RuntimeDir = $env:VC_REDIST_DIR,
  [switch]$StageOnly
)
$ErrorActionPreference = 'Stop'
$Root = (Resolve-Path "$PSScriptRoot\..\..").Path
. "$Root\native\utils\windows_build.ps1"

# 将相对参数统一解释为仓库路径，支持从其他工作目录调用。
function Resolve-RepoPath([string]$Path) {
  if ([IO.Path]::IsPathRooted($Path)) { return [IO.Path]::GetFullPath($Path) }
  return [IO.Path]::GetFullPath((Join-Path $Root $Path))
}

# 依次查找用户指定路径、PATH 与标准安装目录中的 Inno Setup 编译器。
function Find-InstallerCompiler {
  if ($CompilerPath) { return (Resolve-Path -LiteralPath $CompilerPath).Path }
  $command = Get-Command ISCC.exe -ErrorAction SilentlyContinue
  if ($command) { return $command.Source }
  foreach ($base in @(${env:ProgramFiles(x86)}, $env:ProgramFiles)) {
    if ($base) {
      $candidate = Join-Path $base 'Inno Setup 6\ISCC.exe'
      if (Test-Path -LiteralPath $candidate) { return $candidate }
    }
  }
  throw 'Inno Setup 6.5+ not found. Install it or set ISCC to the full path of ISCC.exe.'
}

# 优先使用显式 VC_REDIST_DIR，否则使用当前 Visual Studio 的可再分发运行库。
function Find-RuntimeDirectory {
  if ($RuntimeDir) { return (Resolve-Path -LiteralPath $RuntimeDir).Path }
  if ($env:VCToolsRedistDir) {
    # VS 2022 / 2026 的 CRT 目录名不同，只在当前工具链的目标架构下查找。
    $archDirectory = Join-Path $env:VCToolsRedistDir $Arch
    $candidate = Get-ChildItem -LiteralPath $archDirectory -Directory -Filter 'Microsoft.VC*.CRT' -ErrorAction SilentlyContinue |
      Sort-Object Name -Descending | Select-Object -First 1
    if ($candidate) { return $candidate.FullName }
  }
  throw "VC++ $Arch runtime not found. Use a VS developer shell or set VC_REDIST_DIR to the target architecture CRT directory."
}

if (-not $ReleaseDir) { $ReleaseDir = "build/windows/$Arch/runner/Release" }
$ReleaseDir = Resolve-RepoPath $ReleaseDir
$OutputDir = Resolve-RepoPath $OutputDir
# 每次使用独立暂存目录，避免把旧版本残留文件带入安装包，也不删除已有产物。
$StageDir = Join-Path $Root ("build\packaging\windows-$Arch-" + [Guid]::NewGuid().ToString('N'))
$required = @('remlark.exe', 'flutter_windows.dll', 'remlark_rdp.dll', 'remlark_crypto.dll',
  'sqlite3.dll', 'data\app.so', 'data\icudtl.dat', 'data\flutter_assets')
foreach ($file in $required) {
  if (-not (Test-Path -LiteralPath (Join-Path $ReleaseDir $file))) {
    throw "Incomplete Release bundle, missing: $file"
  }
}
$runtime = Find-RuntimeDirectory
# ARM64 不要求 x64 专用的 FH4 运行库；分发时复制目标架构完整 CRT。
$runtimeFiles = @('msvcp140.dll', 'vcruntime140.dll')
if ($Arch -eq 'x64') { $runtimeFiles += 'vcruntime140_1.dll' }
foreach ($file in $runtimeFiles) {
  if (-not (Test-Path -LiteralPath (Join-Path $runtime $file))) { throw "Missing VC++ runtime: $file" }
}
$compiler = $null
if (-not $StageOnly) { $compiler = Find-InstallerCompiler }
New-Item -ItemType Directory -Force -Path $StageDir, $OutputDir | Out-Null
Get-ChildItem -LiteralPath $ReleaseDir | Copy-Item -Destination $StageDir -Recurse -Force
Get-ChildItem -LiteralPath $runtime -Filter '*.dll' | Copy-Item -Destination $StageDir -Force
if ($StageOnly) { Write-Output $StageDir; exit 0 }

# 与三个平台共享 VERSION 解析，Inno 的资源版本使用四段数字。
$versionJson = & python3 "$Root\tools\utils\app_version.py" json
if ($LASTEXITCODE -ne 0) { throw 'Unable to read VERSION' }
$version = $versionJson | ConvertFrom-Json
$appVersion = $version.name
$resourceVersion = $version.resource
# 防止更改 VERSION 后直接给旧 exe 换名打包，四段资源版本必须匹配。
$exeVersion = (Get-Item -LiteralPath (Join-Path $ReleaseDir 'remlark.exe')).VersionInfo
$actualVersion = @($exeVersion.FileMajorPart, $exeVersion.FileMinorPart, $exeVersion.FileBuildPart, $exeVersion.FilePrivatePart) -join '.'
if ($actualVersion -ne $resourceVersion) { throw 'Release version does not match VERSION; run make windows first.' }
$installerName = "remlark-$appVersion-windows-$Arch-setup"
Invoke-BuildCommand $compiler "/DSourceDir=$StageDir" "/DDistDir=$OutputDir" "/DAppVersion=$appVersion" `
  "/DInstallerArch=$Arch" "/DResourceVersion=$resourceVersion" "/DInstallerName=$installerName" "$PSScriptRoot\remlark.iss"
Compress-Archive -Force -Path "$StageDir\*" -DestinationPath (Join-Path $OutputDir "remlark-windows-$Arch.zip")
Write-Host "Installer: $(Join-Path $OutputDir ($installerName + '.exe'))"
Write-Host "Portable: $(Join-Path $OutputDir "remlark-windows-$Arch.zip")"
