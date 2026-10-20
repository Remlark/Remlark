# 编译 SSH 加密原生库（Windows x64）：remlark_crypto.dll，静态链接 OpenSSL。
# OpenSSL 复用 RDP 原生库构建产物（build\native\windows-x86_64\prefix），需先执行 native\rdp\scripts\build.ps1
# 需要：Visual Studio 2022（在 "x64 Native Tools Command Prompt" 中运行）、CMake、Ninja
# 用法：powershell -ExecutionPolicy Bypass -File native\ssh_crypto\scripts\build.ps1
$ErrorActionPreference = "Stop"

$Root = (Resolve-Path "$PSScriptRoot\..\..\..").Path
$Native = "$Root\native\ssh_crypto"
$Out = "$Root\build\native\windows-x86_64"
$Prefix = "$Out\prefix"
if (-not (Test-Path "$Prefix\lib\libcrypto.lib")) {
  throw "缺少 $Prefix\lib\libcrypto.lib，请先编译 RDP 原生库（make rdp-lib）"
}

cmake -G Ninja -S $Native -B "$Out\crypto-build" -DCMAKE_BUILD_TYPE=Release "-DREMLARK_DEPS_PREFIX=$Prefix" `
  -DCMAKE_MSVC_RUNTIME_LIBRARY=MultiThreaded
cmake --build "$Out\crypto-build"
Copy-Item "$Out\crypto-build\remlark_crypto.dll" "$Out\remlark_crypto.dll" -Force
Write-Host "==> $Out\remlark_crypto.dll"
