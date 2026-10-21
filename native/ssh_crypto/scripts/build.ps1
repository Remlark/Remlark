# 编译 SSH 加密原生库（Windows x64 / arm64）：remlark_crypto.dll，静态链接 OpenSSL。
# OpenSSL 复用 RDP 原生库构建产物（build\native\windows-<架构>\prefix），需先用相同架构执行 native\rdp\scripts\build.ps1
# 需要：Visual Studio 2022（在对应架构的 Native Tools Command Prompt 中运行）、CMake、Ninja
# 用法：powershell -ExecutionPolicy Bypass -File native\ssh_crypto\scripts\build.ps1 [-Arch x86_64|arm64]
param(
  # 目标架构：x86_64 / arm64，默认取 VS 开发者命令行的目标架构（VSCMD_ARG_TGT_ARCH），没有时取本机架构
  [ValidateSet("x86_64", "arm64")] [string]$Arch
)
$ErrorActionPreference = "Stop"

# 目标架构必须与当前 VS 开发者命令行一致（cl.exe 只能编译当前环境的目标架构）
$VsTarget = $env:VSCMD_ARG_TGT_ARCH
if (-not $Arch) {
  if ($VsTarget -eq "arm64") { $Arch = "arm64" }
  elseif ($VsTarget -eq "x64") { $Arch = "x86_64" }
  elseif ($env:PROCESSOR_ARCHITECTURE -eq "ARM64") { $Arch = "arm64" }
  else { $Arch = "x86_64" }
}
$ExpectedVs = @{ "x86_64" = "x64"; "arm64" = "arm64" }[$Arch]
if ($VsTarget -and $VsTarget -ne $ExpectedVs) {
  throw "当前 VS 命令行的目标架构为 $VsTarget，编译 $Arch 请在 `"$ExpectedVs Native Tools Command Prompt`"（或 x64_arm64 交叉编译命令行）中运行"
}

$Root = (Resolve-Path "$PSScriptRoot\..\..\..").Path
$Native = "$Root\native\ssh_crypto"
$Out = "$Root\build\native\windows-$Arch"
$Prefix = "$Out\prefix"
if (-not (Test-Path "$Prefix\lib\libcrypto.lib")) {
  throw "缺少 $Prefix\lib\libcrypto.lib，请先编译 RDP 原生库（make rdp-lib）"
}

cmake -G Ninja -S $Native -B "$Out\crypto-build" -DCMAKE_BUILD_TYPE=Release "-DREMLARK_DEPS_PREFIX=$Prefix" `
  -DCMAKE_MSVC_RUNTIME_LIBRARY=MultiThreaded
cmake --build "$Out\crypto-build"
Copy-Item "$Out\crypto-build\remlark_crypto.dll" "$Out\remlark_crypto.dll" -Force
Write-Host "==> $Out\remlark_crypto.dll"
