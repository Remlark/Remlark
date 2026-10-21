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