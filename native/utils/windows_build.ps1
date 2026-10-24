# 执行原生命令并检查退出码；Windows PowerShell 5.1 不会因外部命令失败而自动停止。
function Invoke-BuildCommand {
  # 直接使用自动变量 args，避免 tar 的 -C、编译器的 -Command 等参数被 PowerShell 绑定到包装器。
  $Executable = $args[0]
  $CommandArguments = @($args | Select-Object -Skip 1)
  # GNU Make 会导出自己的 MAKEFLAGS；NMake 不能解析其中的 -- 与命令行变量。
  $isNmake = [IO.Path]::GetFileNameWithoutExtension($Executable) -in @('nmake', 'jom')
  $savedMakeFlags = $env:MAKEFLAGS
  try {
    if ($isNmake) { Remove-Item Env:MAKEFLAGS -ErrorAction SilentlyContinue }
    & $Executable @CommandArguments
    $commandExitCode = $LASTEXITCODE
  } finally {
    if ($isNmake) { $env:MAKEFLAGS = $savedMakeFlags }
  }
  if ($commandExitCode -ne 0) {
    throw "Build command failed ($commandExitCode): $Executable $CommandArguments"
  }
}

# 在耗时构建前检查全部必需工具，缺失时立即指出具体命令。
function Assert-BuildTools([string[]]$Tools) {
  foreach ($tool in $Tools) {
    if (-not (Get-Command $tool -ErrorAction SilentlyContinue)) {
      throw "Missing native build tool: $tool"
    }
  }
}

# 状态 1 表示阶段未完成；工具本身异常不得被当作需要重新编译而继续消耗时间。
function Test-NativeStage([string]$State, [string]$Output, [string]$Stage) {
  & python3 $State ready $Output windows $Stage
  if ($LASTEXITCODE -gt 1) { throw "Cannot inspect native stage: $Stage" }
  return ($LASTEXITCODE -eq 0)
}

# 使用预处理器实际确认 cl 的目标架构，避免开发者环境变量缺失或过期时编译错架构。
function Assert-ClTarget([string]$Architecture) {
  $probe = [IO.Path]::GetTempFileName()
  try {
    $source = "#if defined(_M_ARM64)`nREMLARK_ARM64`n#elif defined(_M_X64)`nREMLARK_X64`n#else`nREMLARK_UNSUPPORTED`n#endif`n"
    [IO.File]::WriteAllText($probe, $source, [Text.Encoding]::ASCII)
    $actual = @(& cl /nologo /EP /TC $probe)
    if ($LASTEXITCODE -ne 0) { throw 'Cannot inspect MSVC target architecture' }
    $expected = if ($Architecture -eq 'arm64') { 'REMLARK_ARM64' } else { 'REMLARK_X64' }
    if ($expected -notin @($actual | ForEach-Object { $_.Trim() })) {
      throw "MSVC compiler target does not match $Architecture"
    }
  } finally { Remove-Item -Force $probe -ErrorAction SilentlyContinue }
}
