# 编译 RDP 原生库（Windows x64 / arm64）：OpenSSL + FreeRDP（静态）+ 胶水库 remlark_rdp.dll
# 需要：Visual Studio 2022（含对应架构的 C++ 工具链，x64 在 "x64 Native Tools Command Prompt"、
#       arm64 在 "ARM64 Native Tools Command Prompt" 或 x64_arm64 交叉编译命令行中运行）、CMake、Ninja、
#       Strawberry Perl 与 NASM（x64 编译 OpenSSL 汇编用）
# 用法：powershell -ExecutionPolicy Bypass -File native\rdp\scripts\build.ps1 [-Arch x86_64|arm64]
param(
  # 目标架构：x86_64 / arm64，默认取 VS 开发者命令行的目标架构（VSCMD_ARG_TGT_ARCH），没有时取本机架构
  [ValidateSet("x86_64", "arm64")] [string]$Arch
)
$ErrorActionPreference = "Stop"
$ProgressPreference = "SilentlyContinue"
. "$PSScriptRoot\..\..\..\native\utils\windows_build.ps1"

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

$FreeRdpVersion = "3.32.2"
$OpenSslVersion = "3.6.5"
$ZlibVersion = "1.3.1"
$Root = (Resolve-Path "$PSScriptRoot\..\..\..").Path
$Native = "$Root\native\rdp"
$DepsSrc = "$Native\.deps"
# 输出目录与 hook/build.dart 一致：windows-x86_64 / windows-arm64
$Out = "$Root\build\native\windows-$Arch"
$Prefix = "$Out\prefix"
New-Item -ItemType Directory -Force -Path $DepsSrc, $Out | Out-Null

function Fetch($url, $dir) {
  if (-not (Test-Path "$DepsSrc\$dir")) {
    Write-Host "==> download $url"
    $tar = "$DepsSrc\$dir.tar.gz"
    Invoke-WebRequest -Uri $url -OutFile $tar
    Invoke-BuildCommand "$env:SystemRoot\System32\tar.exe" -xzf $tar -C $DepsSrc
  }
}
Fetch "https://github.com/openssl/openssl/releases/download/openssl-$OpenSslVersion/openssl-$OpenSslVersion.tar.gz" "openssl-$OpenSslVersion"
Fetch "https://github.com/FreeRDP/FreeRDP/archive/refs/tags/$FreeRdpVersion.tar.gz" "FreeRDP-$FreeRdpVersion"

# 1. OpenSSL（静态，/MT）
if (-not (Test-Path "$Prefix\lib\libcrypto.lib")) {
  $build = "$Out\openssl-build"
  if (Test-Path $build) { Remove-Item -Recurse -Force $build }
  Copy-Item -Recurse "$DepsSrc\openssl-$OpenSslVersion" $build
  Push-Location $build
  $OpenSslTarget = @{ "x86_64" = "VC-WIN64A"; "arm64" = "VC-WIN64-ARM" }[$Arch]
  # /FS 同步多个 cl 进程对共享 PDB 的写入，支持 JOM 并行构建。
  Invoke-BuildCommand perl Configure $OpenSslTarget /FS no-shared no-tests no-docs no-apps "--prefix=$Prefix" "--openssldir=$Prefix\ssl" --libdir=lib
  # JOM 兼容 NMake 并支持并行构建；未安装时保持 NMake 入口。
  $makeCommand = if (Get-Command jom -ErrorAction SilentlyContinue) { 'jom' } else { 'nmake' }
  Invoke-BuildCommand $makeCommand
  Invoke-BuildCommand $makeCommand install_sw
  Pop-Location
}

# 2. zlib（FreeRDP 必需，静态链接到胶水库；与 OpenSSL 一样使用 /MT）
if (-not (Test-Path "$Prefix\lib\zlibstatic.lib")) {
  Fetch "https://zlib.net/fossils/zlib-$ZlibVersion.tar.gz" "zlib-$ZlibVersion"
  Invoke-BuildCommand cmake -G Ninja -DCMAKE_C_COMPILER=cl -DCMAKE_CXX_COMPILER=cl `
    -S "$DepsSrc\zlib-$ZlibVersion" -B "$Out\zlib-build" -DCMAKE_BUILD_TYPE=Release `
    "-DCMAKE_INSTALL_PREFIX=$Prefix" -DCMAKE_POLICY_DEFAULT_CMP0091=NEW `
    -DCMAKE_MSVC_RUNTIME_LIBRARY=MultiThreaded -DZLIB_BUILD_EXAMPLES=OFF
  Invoke-BuildCommand cmake --build "$Out\zlib-build"
  Invoke-BuildCommand cmake --install "$Out\zlib-build"
}

# 3. FreeRDP（静态）
if (-not (Test-Path "$Prefix\lib\freerdp3.lib")) {
  Invoke-BuildCommand cmake -G Ninja -DCMAKE_C_COMPILER=cl -DCMAKE_CXX_COMPILER=cl -S "$DepsSrc\FreeRDP-$FreeRdpVersion" -B "$Out\freerdp-build" `
    -DCMAKE_BUILD_TYPE=Release "-DCMAKE_INSTALL_PREFIX=$Prefix" "-DCMAKE_PREFIX_PATH=$Prefix" `
    -DUSE_VERSION_FROM_GIT_TAG=OFF -DBUILD_SHARED_LIBS=OFF -DBUILD_TESTING=OFF -DMSVC_RUNTIME=static -DWITH_CCACHE=OFF `
    "-DZLIB_LIBRARY=$Prefix\lib\zlibstatic.lib" "-DZLIB_INCLUDE_DIR=$Prefix\include" `
    "-DOPENSSL_ROOT_DIR=$Prefix" -DOPENSSL_USE_STATIC_LIBS=ON -DOPENSSL_MSVC_STATIC_RT=ON `
    -DWITH_CLIENT_COMMON=ON -DWITH_CLIENT=OFF -DWITH_CLIENT_SDL=OFF -DWITH_SERVER=OFF -DWITH_SAMPLE=OFF `
    -DWITH_PROXY=OFF -DWITH_SHADOW=OFF -DWITH_PLATFORM_SERVER=OFF -DWITH_FFMPEG=OFF -DWITH_SWSCALE=OFF `
    -DWITH_MEDIA_FOUNDATION=OFF -DWITH_OPENH264=OFF -DWITH_JSON_DISABLED=ON -DWITH_AAD=OFF -DWITH_KRB5=OFF `
    -DWITH_OPUS=OFF -DWITH_URIPARSER=OFF -DWITH_MANPAGES=OFF -DWITH_WINPR_TOOLS=OFF -DWITH_WEBVIEW=OFF `
    -DWITH_INTERNAL_MD4=ON -DWITH_INTERNAL_MD5=ON -DWITH_INTERNAL_RC4=ON `
    -DCHANNEL_URBDRC=OFF -DCHANNEL_AUDIN=OFF -DCHANNEL_TSMF=OFF -DCHANNEL_SMARTCARD=OFF -DCHANNEL_PRINTER=OFF `
    -DCHANNEL_SERIAL=OFF -DCHANNEL_PARALLEL=OFF -DCHANNEL_RDPECAM=OFF -DCHANNEL_SSHAGENT=OFF -DCHANNEL_RDPEAR=OFF
  Invoke-BuildCommand cmake --build "$Out\freerdp-build"
  Invoke-BuildCommand cmake --install "$Out\freerdp-build"
}

# 4. 胶水库
Invoke-BuildCommand cmake -G Ninja -DCMAKE_C_COMPILER=cl -DCMAKE_CXX_COMPILER=cl -S $Native -B "$Out\shim-build" -DCMAKE_BUILD_TYPE=Release "-DREMLARK_DEPS_PREFIX=$Prefix" `
  -DCMAKE_MSVC_RUNTIME_LIBRARY=MultiThreaded
Invoke-BuildCommand cmake --build "$Out\shim-build"
Copy-Item "$Out\shim-build\remlark_rdp.dll" "$Out\remlark_rdp.dll" -Force
Write-Host "==> $Out\remlark_rdp.dll"
