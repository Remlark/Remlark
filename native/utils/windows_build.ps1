# 执行原生命令并检查退出码；Windows PowerShell 5.1 不会因外部命令失败而自动停止。
function Invoke-BuildCommand {
  # 直接使用自动变量 args，避免 tar 的 -C、编译器的 -Command 等参数被 PowerShell 绑定到包装器。
  $Executable = $args[0]
  $CommandArguments = @($args | Select-Object -Skip 1)
  & $Executable @CommandArguments
  if ($LASTEXITCODE -ne 0) {
    throw "Build command failed ($LASTEXITCODE): $Executable $CommandArguments"
  }
}