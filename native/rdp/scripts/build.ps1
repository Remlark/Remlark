# 编译 RDP 原生库（Windows x64）：OpenSSL + FreeRDP（静态）+ 胶水库 remlark_rdp.dll
# 需要：Visual Studio 2022（含 C++ 工具链，在 "x64 Native Tools Command Prompt" 中运行）、CMake、Ninja、
#       Strawberry Perl 与 NASM（编译 OpenSSL 用）
# 用法：powershell -ExecutionPolicy Bypass -File native\rdp\scripts\build.ps1
$ErrorActionPreference = "Stop"

$FreeRdpVersion = "3.32.2"
$OpenSslVersion = "3.6.5"
$Root = (Resolve-Path "$PSScriptRoot\..\..\..").Path
$Native = "$Root\native\rdp"
$DepsSrc = "$Native\.deps"
$Out = "$Root\build\native\windows-x86_64"
$Prefix = "$Out\prefix"
New-Item -ItemType Directory -Force -Path $DepsSrc, $Out | Out-Null

function Fetch($url, $dir) {
  if (-not (Test-Path "$DepsSrc\$dir")) {
    Write-Host "==> download $url"
    $tar = "$DepsSrc\$dir.tar.gz"
    Invoke-WebRequest -Uri $url -OutFile $tar
    tar -xzf $tar -C $DepsSrc
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
  perl Configure VC-WIN64A no-shared no-tests no-docs no-apps "--prefix=$Prefix" "--openssldir=$Prefix\ssl"
  nmake
  nmake install_sw
  Pop-Location
}

# 2. FreeRDP（静态）
if (-not (Test-Path "$Prefix\lib\freerdp3.lib")) {
  cmake -G Ninja -S "$DepsSrc\FreeRDP-$FreeRdpVersion" -B "$Out\freerdp-build" `
    -DCMAKE_BUILD_TYPE=Release "-DCMAKE_INSTALL_PREFIX=$Prefix" "-DCMAKE_PREFIX_PATH=$Prefix" `
    -DBUILD_SHARED_LIBS=OFF -DBUILD_TESTING=OFF -DMSVC_RUNTIME=static `
    "-DOPENSSL_ROOT_DIR=$Prefix" -DOPENSSL_USE_STATIC_LIBS=ON -DOPENSSL_MSVC_STATIC_RT=ON `
    -DWITH_CLIENT_COMMON=ON -DWITH_CLIENT=OFF -DWITH_CLIENT_SDL=OFF -DWITH_SERVER=OFF -DWITH_SAMPLE=OFF `
    -DWITH_PROXY=OFF -DWITH_SHADOW=OFF -DWITH_PLATFORM_SERVER=OFF -DWITH_FFMPEG=OFF -DWITH_SWSCALE=OFF `
    -DWITH_MEDIA_FOUNDATION=OFF -DWITH_OPENH264=OFF -DWITH_JSON_DISABLED=ON -DWITH_AAD=OFF -DWITH_KRB5=OFF `
    -DWITH_OPUS=OFF -DWITH_URIPARSER=OFF -DWITH_MANPAGES=OFF -DWITH_WINPR_TOOLS=OFF -DWITH_WEBVIEW=OFF `
    -DWITH_INTERNAL_MD4=ON -DWITH_INTERNAL_MD5=ON -DWITH_INTERNAL_RC4=ON `
    -DCHANNEL_URBDRC=OFF -DCHANNEL_AUDIN=OFF -DCHANNEL_TSMF=OFF -DCHANNEL_SMARTCARD=OFF -DCHANNEL_PRINTER=OFF `
    -DCHANNEL_SERIAL=OFF -DCHANNEL_PARALLEL=OFF -DCHANNEL_RDPECAM=OFF -DCHANNEL_SSHAGENT=OFF -DCHANNEL_RDPEAR=OFF
  cmake --build "$Out\freerdp-build"
  cmake --install "$Out\freerdp-build"
}

# 3. 胶水库
cmake -G Ninja -S $Native -B "$Out\shim-build" -DCMAKE_BUILD_TYPE=Release "-DREMLARK_DEPS_PREFIX=$Prefix" `
  -DCMAKE_MSVC_RUNTIME_LIBRARY=MultiThreaded
cmake --build "$Out\shim-build"
Copy-Item "$Out\shim-build\remlark_rdp.dll" "$Out\remlark_rdp.dll" -Force
Write-Host "==> $Out\remlark_rdp.dll"
