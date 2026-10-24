# 编译 RDP 原生库（Windows x64 / arm64）：OpenSSL + FFmpeg + FreeRDP（静态）+ 胶水库 remlark_rdp.dll
# 需要：Visual Studio 2022（含对应架构的 C++ 工具链，x64 在 "x64 Native Tools Command Prompt"、
#       arm64 在 "ARM64 Native Tools Command Prompt" 或 x64_arm64 交叉编译命令行中运行）、CMake、Ninja、
#       Strawberry Perl 与 NASM（x64 编译 OpenSSL / FFmpeg 汇编用）、
#       MSYS2（含 make、diffutils，只用来运行 FFmpeg 的 configure；默认 C:\msys64，可用 MSYS2_ROOT 指定）
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
$FfmpegVersion = "8.1.3"
# FreeRDP 编译特性标识：修改 FreeRDP 编译选项时同步修改，已有缓存会自动重新编译
$FreeRdpFeatures = "h264-ffmpeg-hwaccel-1"
$Root = (Resolve-Path "$PSScriptRoot\..\..\..").Path
$Native = "$Root\native\rdp"
$DepsSrc = "$Native\.deps"
# 输出目录与 hook/build.dart 一致：windows-x86_64 / windows-arm64
$Out = "$Root\build\native\windows-$Arch"
$Prefix = "$Out\prefix"
New-Item -ItemType Directory -Force -Path $DepsSrc, $Out | Out-Null
$State = "$Root\tools\utils\native_build_state.py"
Assert-BuildTools @('python3', 'cl', 'link', 'lib', 'cmake', 'ninja', 'nmake', 'perl')
Assert-ClTarget $Arch
if ($Arch -eq 'x86_64') { Assert-BuildTools @('nasm') }
if (-not (Test-Path "$env:SystemRoot\System32\tar.exe")) { throw 'System tar.exe not found' }
Invoke-BuildCommand python3 $State invalidate $Out windows rdp
Invoke-BuildCommand python3 $State invalidate $Out windows crypto
# MSYS2 及编译器语言检查必须在下载、OpenSSL 编译之前执行。
$Msys = if ($env:MSYS2_ROOT) { $env:MSYS2_ROOT } else { "C:\msys64" }
$Bash = "$Msys\usr\bin\bash.exe"
if (-not (Test-NativeStage $State $Out 'ffmpeg')) {
  if (-not (Test-Path $Bash)) { throw "MSYS2 bash not found: $Bash" }
  Invoke-BuildCommand $Bash "$Native\scripts\build_ffmpeg_msvc.sh" --check-toolchain
}

function Fetch($url, $dir, $required, $fallback = $null, $sha256 = $null) {
  # 三平台共享下载校验；有效压缩包才能进入系统 tar，异常响应重试并切换来源。
  Write-Host "==> download $url"
  $tar = "$DepsSrc\$dir.tar.gz"
  $downloadArguments = @("$Root\tools\utils\source_archive.py", $tar, $url)
  if ($fallback) { $downloadArguments += $fallback }
  $downloadArguments += @('--root', $dir)
  $downloadArguments += @('--extract', '--required', $required, '--tar', "$env:SystemRoot\System32\tar.exe")
  if ($sha256) { $downloadArguments += @('--sha256', $sha256) }
  Invoke-BuildCommand python3 @downloadArguments
}
$FeaturesFile = "$Out\freerdp-features"
if (-not (Test-Path $FeaturesFile) -or (Get-Content $FeaturesFile -Raw).Trim() -ne $FreeRdpFeatures) {
  Invoke-BuildCommand python3 $State invalidate $Out windows freerdp
}
if (-not (Test-NativeStage $State $Out 'openssl')) {
  Fetch "https://github.com/openssl/openssl/releases/download/openssl-$OpenSslVersion/openssl-$OpenSslVersion.tar.gz" "openssl-$OpenSslVersion" 'Configure'
}
if (-not (Test-NativeStage $State $Out 'freerdp')) {
  Fetch "https://github.com/FreeRDP/FreeRDP/archive/refs/tags/$FreeRdpVersion.tar.gz" "FreeRDP-$FreeRdpVersion" 'CMakeLists.txt'
}

# 先验证所有尚需编译的源码，下载失败不再等到耗时 OpenSSL 编译之后才暴露。
if (-not (Test-NativeStage $State $Out 'zlib')) {
  Fetch "https://github.com/madler/zlib/releases/download/v$ZlibVersion/zlib-$ZlibVersion.tar.gz" "zlib-$ZlibVersion" 'CMakeLists.txt' `
    "https://zlib.net/fossils/zlib-$ZlibVersion.tar.gz" '9a93b2b7dfdac77ceba5a558a580e74667dd6fede4585b91eefb60f03b72df23'
}
if (-not (Test-NativeStage $State $Out 'ffmpeg')) {
  Fetch "https://ffmpeg.org/releases/ffmpeg-$FfmpegVersion.tar.gz" "ffmpeg-$FfmpegVersion" 'configure'
}

# FreeRDP 3.32.2 的硬解分支在块末尾留下空标签，MSVC 的 C11 不接受；补空语句，重复构建不重复修改。
if (-not (Test-NativeStage $State $Out 'freerdp')) {
  $H264Source = "$DepsSrc\FreeRDP-$FreeRdpVersion\libfreerdp\codec\h264_ffmpeg.c"
  $H264Code = [IO.File]::ReadAllText($H264Source)
  $H264Patched = $H264Code -replace 'fail_hwdevice_create:([ \t]*\r?\n)', 'fail_hwdevice_create:;$1'
  if ($H264Patched -ne $H264Code) {
    [IO.File]::WriteAllText($H264Source, $H264Patched, [Text.UTF8Encoding]::new($false))
  }
}

# 1. OpenSSL（静态，/MT）
if (-not (Test-NativeStage $State $Out 'openssl')) {
  Invoke-BuildCommand python3 $State begin $Out windows openssl
  $build = "$Out\openssl-build"
  if (Test-Path $build) { Remove-Item -Recurse -Force $build }
  Copy-Item -Recurse "$DepsSrc\openssl-$OpenSslVersion" $build
  Push-Location $build
  try {
    $OpenSslTarget = @{ "x86_64" = "VC-WIN64A"; "arm64" = "VC-WIN64-ARM" }[$Arch]
    # /FS 同步多个 cl 进程对共享 PDB 的写入，支持 JOM 并行构建。
    Invoke-BuildCommand perl Configure $OpenSslTarget /FS no-shared no-tests no-docs no-apps "--prefix=$Prefix" "--openssldir=$Prefix\ssl" --libdir=lib
    # JOM 兼容 NMake 并支持并行构建；未安装时保持 NMake 入口。
    $makeCommand = if (Get-Command jom -ErrorAction SilentlyContinue) { 'jom' } else { 'nmake' }
    Invoke-BuildCommand $makeCommand
    # install_sw 会更新依赖 Makefile，使用串行 NMake 避免 JOM 并发重命名冲突。
    Invoke-BuildCommand nmake install_sw
    Invoke-BuildCommand python3 $State mark $Out windows openssl
  } finally { Pop-Location }
}

# 2. zlib（FreeRDP 必需，静态链接到胶水库；与 OpenSSL 一样使用 /MT）
if (-not (Test-NativeStage $State $Out 'zlib')) {
  Invoke-BuildCommand python3 $State begin $Out windows zlib
  if (Test-Path "$Out\zlib-build") { Remove-Item -Recurse -Force "$Out\zlib-build" }
  Invoke-BuildCommand cmake -G Ninja -DCMAKE_C_COMPILER=cl -DCMAKE_CXX_COMPILER=cl `
    -S "$DepsSrc\zlib-$ZlibVersion" -B "$Out\zlib-build" -DCMAKE_BUILD_TYPE=Release `
    "-DCMAKE_INSTALL_PREFIX=$Prefix" -DCMAKE_POLICY_DEFAULT_CMP0091=NEW `
    -DCMAKE_MSVC_RUNTIME_LIBRARY=MultiThreaded -DZLIB_BUILD_EXAMPLES=OFF
  Invoke-BuildCommand cmake --build "$Out\zlib-build"
  Invoke-BuildCommand cmake --install "$Out\zlib-build"
  Invoke-BuildCommand python3 $State mark $Out windows zlib
}

# 3. FFmpeg（静态，/MT）：只保留 H.264 解码器、解析器与 swscale，开启 D3D11VA / DXVA2 硬件解码
if (-not (Test-NativeStage $State $Out 'ffmpeg')) {
  Invoke-BuildCommand python3 $State begin $Out windows ffmpeg
  Invoke-BuildCommand $Bash "$Native\scripts\build_ffmpeg_msvc.sh" "$DepsSrc\ffmpeg-$FfmpegVersion" "$Out\ffmpeg-build" $Prefix $Arch
  Invoke-BuildCommand python3 $State mark $Out windows ffmpeg
}
# MSVC 工具链已直接生成 xxx.lib；检查全部产物，不按 MinGW 的 libxxx.a 命名重命名。
foreach ($lib in @("avcodec", "swscale", "avutil")) {
  if (-not (Test-Path "$Prefix\lib\$lib.lib")) {
    throw "FFmpeg MSVC static library missing: $Prefix\lib\$lib.lib"
  }
}

# 4. FreeRDP（静态）
# 编译选项变化（特性标识不同）时清理旧缓存重新编译
$FeaturesFile = "$Out\freerdp-features"
if ((Test-Path "$Prefix\lib\freerdp3.lib") -and
    (-not (Test-Path $FeaturesFile) -or (Get-Content $FeaturesFile -Raw).Trim() -ne $FreeRdpFeatures)) {
  foreach ($path in @("$Out\freerdp-build", "$Prefix\lib\freerdp3.lib")) {
    if (Test-Path $path) { Remove-Item -Recurse -Force $path }
  }
}
if (-not (Test-NativeStage $State $Out 'freerdp')) {
  Invoke-BuildCommand python3 $State begin $Out windows freerdp
  if (Test-Path "$Out\freerdp-build") { Remove-Item -Recurse -Force "$Out\freerdp-build" }
  Invoke-BuildCommand cmake -G Ninja -DCMAKE_C_COMPILER=cl -DCMAKE_CXX_COMPILER=cl -S "$DepsSrc\FreeRDP-$FreeRdpVersion" -B "$Out\freerdp-build" `
    -DCMAKE_BUILD_TYPE=Release "-DCMAKE_INSTALL_PREFIX=$Prefix" "-DCMAKE_PREFIX_PATH=$Prefix" `
    -DUSE_VERSION_FROM_GIT_TAG=OFF -DBUILD_SHARED_LIBS=OFF -DBUILD_TESTING=OFF -DMSVC_RUNTIME=static -DWITH_CCACHE=OFF `
    "-DZLIB_LIBRARY=$Prefix\lib\zlibstatic.lib" "-DZLIB_INCLUDE_DIR=$Prefix\include" `
    "-DOPENSSL_ROOT_DIR=$Prefix" -DOPENSSL_USE_STATIC_LIBS=ON -DOPENSSL_MSVC_STATIC_RT=ON `
    -DWITH_CLIENT_COMMON=ON -DWITH_CLIENT=OFF -DWITH_CLIENT_SDL=OFF -DWITH_SERVER=OFF -DWITH_SAMPLE=OFF `
    -DWITH_PROXY=OFF -DWITH_SHADOW=OFF -DWITH_PLATFORM_SERVER=OFF `
    -DWITH_FFMPEG=ON -DWITH_VIDEO_FFMPEG=ON -DWITH_DSP_FFMPEG=OFF -DWITH_FFMPEG_HWACCEL=ON -DWITH_SWSCALE=ON `
    -DWITH_MEDIA_FOUNDATION=OFF -DWITH_OPENH264=OFF -DWITH_JSON_DISABLED=ON -DWITH_AAD=OFF -DWITH_KRB5=OFF `
    -DWITH_OPUS=OFF -DWITH_URIPARSER=OFF -DWITH_MANPAGES=OFF -DWITH_WINPR_TOOLS=OFF -DWITH_WEBVIEW=OFF `
    -DWITH_INTERNAL_MD4=ON -DWITH_INTERNAL_MD5=ON -DWITH_INTERNAL_RC4=ON `
    -DCHANNEL_URBDRC=OFF -DCHANNEL_AUDIN=OFF -DCHANNEL_TSMF=OFF -DCHANNEL_SMARTCARD=OFF -DCHANNEL_PRINTER=OFF `
    -DCHANNEL_SERIAL=OFF -DCHANNEL_PARALLEL=OFF -DCHANNEL_RDPECAM=OFF -DCHANNEL_SSHAGENT=OFF -DCHANNEL_RDPEAR=OFF
  Invoke-BuildCommand cmake --build "$Out\freerdp-build"
  Invoke-BuildCommand cmake --install "$Out\freerdp-build"
  Set-Content -Path $FeaturesFile -Value $FreeRdpFeatures -Encoding ascii
  Invoke-BuildCommand python3 $State mark $Out windows freerdp
}

# 5. 胶水库
Invoke-BuildCommand python3 $State begin $Out windows rdp
Invoke-BuildCommand cmake -G Ninja -DCMAKE_C_COMPILER=cl -DCMAKE_CXX_COMPILER=cl -S $Native -B "$Out\shim-build" -DCMAKE_BUILD_TYPE=Release "-DREMLARK_DEPS_PREFIX=$Prefix" `
  -DCMAKE_MSVC_RUNTIME_LIBRARY=MultiThreaded
Invoke-BuildCommand cmake --build "$Out\shim-build"
Copy-Item "$Out\shim-build\remlark_rdp.dll" "$Out\remlark_rdp.dll" -Force
Invoke-BuildCommand python3 $State mark $Out windows rdp
Write-Host "==> $Out\remlark_rdp.dll"
