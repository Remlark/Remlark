# 本地 PowerShell 故障回归：不启动产品构建、不访问公网，兼容 Windows PowerShell 5.1。
$ErrorActionPreference = 'Stop'
$Root = (Resolve-Path "$PSScriptRoot\..\..").Path
. "$Root\native\utils\windows_build.ps1"
$work = Join-Path ([IO.Path]::GetTempPath()) ('remlark ps 中文 ' + [Guid]::NewGuid())
$originalSystemRoot = $env:SystemRoot
$windowsHost = [Environment]::OSVersion.Platform -eq [PlatformID]::Win32NT
New-Item -ItemType Directory -Path $work | Out-Null
try {
  # 确认原始包装器保留参数和失败退出码，不将原生命令失败当成成功。
  Invoke-BuildCommand python3 -c 'import sys; assert sys.argv[1] == chr(45)+chr(67)' -C
  $rejected = $false
  try { Invoke-BuildCommand python3 -c 'import sys; sys.exit(7)' } catch {
    if ($_.Exception.Message -notlike '*failed (7)*') { throw }
    $rejected = $true
  }
  if (-not $rejected) { throw 'Native failure was ignored' }
  function cl { $global:LASTEXITCODE = 0; 'REMLARK_ARM64' }
  Assert-ClTarget arm64
  $rejected = $false
  try { Assert-ClTarget x86_64 } catch { $rejected = $true }
  if (-not $rejected) { throw 'Wrong compiler target was accepted' }
  $rejected = $false
  try { Assert-BuildTools @('remlark-definitely-missing-tool') } catch { $rejected = $true }
  if (-not $rejected) { throw 'Missing tool was accepted' }

  # 执行真实 Windows 驱动的缺工具分支，必须在任何下载及编译前失败。
  $probeRepo = Join-Path $work 'preflight-repo'
  $probeScripts = Join-Path $probeRepo 'native/rdp/scripts'
  $probeUtils = Join-Path $probeRepo 'native/utils'
  New-Item -ItemType Directory -Force -Path $probeScripts, $probeUtils | Out-Null
  Copy-Item (Join-Path $Root 'native/rdp/scripts/build.ps1') $probeScripts
  Copy-Item (Join-Path $Root 'native/utils/windows_build.ps1') $probeUtils
  $savedPath = $env:PATH
  $rejected = $false
  try {
    $env:PATH = ''
    $target = if ($env:VSCMD_ARG_TGT_ARCH -eq 'arm64') { 'arm64' } else { 'x86_64' }
    try { & (Join-Path $probeScripts 'build.ps1') -Arch $target } catch {
      if ($_.Exception.Message -notlike 'Missing native build tool:*') { throw }
      $rejected = $true
    }
  } finally { $env:PATH = $savedPath }
  if (-not $rejected) { throw 'Driver did not reject missing tools before building' }

  # 实际解析发布脚本，仅加载 Fetch 函数，不执行下载/编译主流程。
  $tokens = $null
  $errors = $null
  $tree = [System.Management.Automation.Language.Parser]::ParseFile(
    (Join-Path $Root 'native/rdp/scripts/build.ps1'), [ref]$tokens, [ref]$errors)
  if ($errors.Count) { throw ($errors | Out-String) }
  $fetch = $tree.FindAll({ param($node)
    $node -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -eq 'Fetch'
  }, $true)
  if ($fetch.Count -ne 1) { throw 'Expected one Fetch function' }
  Invoke-Expression $fetch[0].Extent.Text
  $DepsSrc = Join-Path $work 'deps'
  New-Item -ItemType Directory -Path $DepsSrc | Out-Null

  # macOS/Linux 测试仅转换平台分隔符；Windows 实测保留脚本原始路径和 System32 tar。
  $originalCommand = ${function:Invoke-BuildCommand}
  if (-not $windowsHost) {
    function Invoke-BuildCommand {
      $translated = @($args | ForEach-Object { ([string]$_).Replace('\', '/') })
      & $originalCommand @translated
    }
    $env:SystemRoot = Join-Path $work 'Windows'
    $system32 = Join-Path $env:SystemRoot 'System32'
    New-Item -ItemType Directory -Path $system32 | Out-Null
    $tar = Join-Path $system32 'tar.exe'
    [IO.File]::WriteAllText($tar, "#!/bin/sh`nexec /usr/bin/tar " + '"$@"' + "`n", [Text.UTF8Encoding]::new($false))
    & chmod +x $tar
    if ($LASTEXITCODE -ne 0) { throw 'Cannot prepare local tar fixture' }
  }
  $fixtureCode = @'
import io, pathlib, sys, tarfile
path = pathlib.Path(sys.argv[1]) / 'fixture.tar.gz'
with tarfile.open(path, 'w:gz') as archive:
    member = tarfile.TarInfo('zlib-1.3.1/CMakeLists.txt')
    member.size = 4
    archive.addfile(member, io.BytesIO(b'code'))
'@
  Invoke-BuildCommand python3 -c $fixtureCode $work
  $archive = Join-Path $work 'fixture.tar.gz'
  $uri = & python3 -c 'import pathlib,sys; print(pathlib.Path(sys.argv[1]).resolve().as_uri())' $archive
  if ($LASTEXITCODE -ne 0 -or -not $uri) { throw 'Cannot prepare local fixture URI' }
  # 不用 Get-FileHash：从 pwsh 7 启动 5.1 时继承的 PSModulePath 会使该 cmdlet 无法加载。
  $hash = & python3 -c 'import hashlib,pathlib,sys; print(hashlib.sha256(pathlib.Path(sys.argv[1]).read_bytes()).hexdigest())' $archive
  if ($LASTEXITCODE -ne 0 -or -not $hash) { throw 'Cannot hash local fixture' }
  Fetch $uri 'zlib-1.3.1' 'CMakeLists.txt' $uri $hash
  $required = Join-Path $DepsSrc 'zlib-1.3.1/CMakeLists.txt'
  if ((Get-Content -Raw $required) -ne 'code') { throw 'Fetch did not preserve source contents' }
  Remove-Item $required
  Fetch $uri 'zlib-1.3.1' 'CMakeLists.txt' $uri $hash
  if ((Get-Content -Raw $required) -ne 'code') { throw 'Incomplete source was not repaired' }
  Write-Output 'Windows build wrapper checks passed'
} finally {
  $env:SystemRoot = $originalSystemRoot
  Remove-Item -Recurse -Force $work
}
