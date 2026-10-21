#!/usr/bin/env bash
# 编译 RDP 原生库（macOS / Linux）：
#   1. 从源码编译 OpenSSL（静态）
#   2. 从源码编译 FFmpeg（静态，仅 H.264 解码器 + 平台硬件解码：macOS VideoToolbox / Linux VAAPI）
#   3. 从源码编译 FreeRDP（静态，仅客户端核心 + 所需通道，H.264 经 FFmpeg 解码）
#   4. 编译胶水库 libremlark_rdp（动态库，供 Dart FFI 调用）
# 用法：native/rdp/scripts/build.sh [arch]   arch 默认当前架构；macOS 传 universal 生成通用二进制
set -euo pipefail

FREERDP_VERSION=3.32.2
OPENSSL_VERSION=3.6.5
FFMPEG_VERSION=8.1.3
# FreeRDP 编译特性标识：修改 FreeRDP 编译选项时同步修改，已有缓存会自动重新编译
FREERDP_FEATURES="h264-ffmpeg-hwaccel-1"

ROOT="$(cd "$(dirname "$0")/../../.." && pwd)"
NATIVE="$ROOT/native/rdp"
DEPS_SRC="$NATIVE/.deps"
OS="$(uname -s)"
ARCH="${1:-$(uname -m)}"
JOBS="$(getconf _NPROCESSORS_ONLN 2>/dev/null || echo 4)"
export MACOSX_DEPLOYMENT_TARGET=12.0

case "$OS" in
  Darwin) PLATFORM=macos; LIBNAME=libremlark_rdp.dylib ;;
  Linux) PLATFORM=linux; LIBNAME=libremlark_rdp.so ;;
  *) echo "unsupported OS: $OS (Windows 请使用 build.ps1)"; exit 1 ;;
esac

# macOS 通用二进制：分别编译两个架构后合并
if [[ "$PLATFORM" == macos && "$ARCH" == universal ]]; then
  "$0" x86_64
  "$0" arm64
  mkdir -p "$ROOT/build/native/macos"
  lipo -create "$ROOT/build/native/macos-x86_64/$LIBNAME" "$ROOT/build/native/macos-arm64/$LIBNAME" \
    -output "$ROOT/build/native/macos/$LIBNAME"
  echo "universal: $ROOT/build/native/macos/$LIBNAME"
  exit 0
fi

OUT="$ROOT/build/native/$PLATFORM-$ARCH"
PREFIX="$OUT/prefix"
mkdir -p "$DEPS_SRC" "$OUT"

# 下载源码（已存在则跳过）
fetch() {
  local url="$1" dir="$2"
  if [[ ! -d "$DEPS_SRC/$dir" ]]; then
    echo "==> download $url"
    curl -fsSL "$url" | tar xz -C "$DEPS_SRC"
  fi
}
fetch "https://github.com/openssl/openssl/releases/download/openssl-$OPENSSL_VERSION/openssl-$OPENSSL_VERSION.tar.gz" "openssl-$OPENSSL_VERSION"
fetch "https://github.com/FreeRDP/FreeRDP/archive/refs/tags/$FREERDP_VERSION.tar.gz" "FreeRDP-$FREERDP_VERSION"
fetch "https://ffmpeg.org/releases/ffmpeg-$FFMPEG_VERSION.tar.gz" "ffmpeg-$FFMPEG_VERSION"

# 1. OpenSSL
if [[ ! -f "$PREFIX/lib/libcrypto.a" ]]; then
  case "$PLATFORM-$ARCH" in
    macos-x86_64) TARGET=darwin64-x86_64-cc ;;
    macos-arm64) TARGET=darwin64-arm64-cc ;;
    linux-x86_64) TARGET=linux-x86_64 ;;
    linux-aarch64|linux-arm64) TARGET=linux-aarch64 ;;
    *) echo "unsupported arch $ARCH"; exit 1 ;;
  esac
  BUILD_DIR="$OUT/openssl-build"
  rm -rf "$BUILD_DIR" && cp -R "$DEPS_SRC/openssl-$OPENSSL_VERSION" "$BUILD_DIR"
  (cd "$BUILD_DIR" && ./Configure "$TARGET" no-shared no-tests no-docs no-apps -fPIC \
      --prefix="$PREFIX" --libdir=lib >/dev/null && make -j"$JOBS" >/dev/null && make install_sw >/dev/null)
  echo "==> openssl ok"
fi

# 2. FFmpeg（静态）：只保留 H.264 解码器、解析器与 swscale，硬件解码按平台开启
if [[ ! -f "$PREFIX/lib/libavcodec.a" ]]; then
  case "$PLATFORM" in
    macos) FF_HW=(--enable-videotoolbox --enable-hwaccel=h264_videotoolbox) ;;
    linux) FF_HW=(--enable-vaapi --enable-hwaccel=h264_vaapi) ;;
  esac
  FF_CROSS=()
  # macOS 交叉编译另一架构时显式指定目标，避免按主机架构选择汇编
  if [[ "$PLATFORM" == macos && "$ARCH" != "$(uname -m)" ]]; then
    FF_CROSS=(--enable-cross-compile --target-os=darwin --arch="$ARCH" --cc="clang -arch $ARCH")
  elif [[ "$PLATFORM" == macos ]]; then
    FF_CROSS=(--cc="clang -arch $ARCH")
  fi
  BUILD_DIR="$OUT/ffmpeg-build"
  rm -rf "$BUILD_DIR" && mkdir -p "$BUILD_DIR"
  (cd "$BUILD_DIR" && "$DEPS_SRC/ffmpeg-$FFMPEG_VERSION/configure" --prefix="$PREFIX" --libdir="$PREFIX/lib" \
      "${FF_CROSS[@]}" --enable-static --disable-shared --enable-pic --disable-debug --disable-doc \
      --disable-programs --disable-autodetect --disable-everything --disable-network \
      --disable-avdevice --disable-avformat --disable-avfilter --disable-swresample \
      --enable-decoder=h264 --enable-parser=h264 "${FF_HW[@]}" >"$OUT/ffmpeg-configure.log" \
    && make -j"$JOBS" >"$OUT/ffmpeg-build.log" && make install >/dev/null)
  echo "==> ffmpeg ok"
fi

# 3. FreeRDP（静态）
# 编译选项变化（特性标识不同）时清理旧缓存重新编译
if [[ -f "$PREFIX/lib/libfreerdp3.a" && "$(cat "$OUT/freerdp-features" 2>/dev/null)" != "$FREERDP_FEATURES" ]]; then
  rm -rf "$OUT/freerdp-build" "$PREFIX/lib/libfreerdp3.a"
fi
if [[ ! -f "$PREFIX/lib/libfreerdp3.a" ]]; then
  CMAKE_ARCH=()
  [[ "$PLATFORM" == macos ]] && CMAKE_ARCH=(-DCMAKE_OSX_ARCHITECTURES="$ARCH")
  # macOS 交叉编译（例如在 Intel Mac 上编译 arm64）时指定目标处理器，避免按主机架构选择 SIMD
  if [[ "$PLATFORM" == macos && "$ARCH" != "$(uname -m)" ]]; then
    CMAKE_ARCH+=(-DCMAKE_SYSTEM_NAME=Darwin -DCMAKE_SYSTEM_PROCESSOR="$ARCH" -DCMAKE_CROSSCOMPILING=ON)
  fi
  cmake -G Ninja -S "$DEPS_SRC/FreeRDP-$FREERDP_VERSION" -B "$OUT/freerdp-build" "${CMAKE_ARCH[@]}" \
    -DCMAKE_BUILD_TYPE=Release -DCMAKE_INSTALL_PREFIX="$PREFIX" -DCMAKE_PREFIX_PATH="$PREFIX" \
    -DCMAKE_POSITION_INDEPENDENT_CODE=ON -DUSE_VERSION_FROM_GIT_TAG=OFF -DBUILD_SHARED_LIBS=OFF -DBUILD_TESTING=OFF \
    -DOPENSSL_ROOT_DIR="$PREFIX" -DOPENSSL_USE_STATIC_LIBS=ON \
    -DWITH_CLIENT_COMMON=ON -DWITH_CLIENT=OFF -DWITH_CLIENT_SDL=OFF -DWITH_SERVER=OFF -DWITH_SAMPLE=OFF \
    -DWITH_PROXY=OFF -DWITH_SHADOW=OFF -DWITH_PLATFORM_SERVER=OFF -DWITH_X11=OFF -DWITH_WAYLAND=OFF \
    -DWITH_FFMPEG=ON -DWITH_VIDEO_FFMPEG=ON -DWITH_DSP_FFMPEG=OFF -DWITH_FFMPEG_HWACCEL=ON -DWITH_SWSCALE=ON \
    -DWITH_CAIRO=OFF -DWITH_OPENH264=OFF \
    -DWITH_JSON_DISABLED=ON -DWITH_AAD=OFF -DWITH_KRB5=OFF -DWITH_FUSE=OFF -DWITH_PCSC=OFF \
    -DWITH_SMARTCARD_EMULATE=OFF -DWITH_CUPS=OFF -DWITH_PULSE=OFF -DWITH_ALSA=OFF -DWITH_OSS=OFF \
    -DWITH_URIPARSER=OFF -DWITH_OPUS=OFF -DWITH_SOXR=OFF -DWITH_LAME=OFF -DWITH_FAAD2=OFF -DWITH_FAAC=OFF -DWITH_MANPAGES=OFF -DWITH_WINPR_TOOLS=OFF -DWITH_WEBVIEW=OFF \
    -DWITH_UNICODE_BUILTIN=ON -DWITH_INTERNAL_MD4=ON -DWITH_INTERNAL_MD5=ON -DWITH_INTERNAL_RC4=ON \
    -DCHANNEL_URBDRC=OFF -DCHANNEL_AUDIN=OFF -DCHANNEL_TSMF=OFF \
    -DCHANNEL_SMARTCARD=OFF -DCHANNEL_PRINTER=OFF -DCHANNEL_SERIAL=OFF -DCHANNEL_PARALLEL=OFF \
    -DCHANNEL_RDPECAM=OFF -DCHANNEL_SSHAGENT=OFF -DCHANNEL_RDPEAR=OFF >"$OUT/freerdp-configure.log"
  cmake --build "$OUT/freerdp-build" -j"$JOBS" >"$OUT/freerdp-build.log"
  cmake --install "$OUT/freerdp-build" >/dev/null
  echo "$FREERDP_FEATURES" >"$OUT/freerdp-features"
  echo "==> freerdp ok"
fi

# 4. 胶水库
CMAKE_ARCH=()
[[ "$PLATFORM" == macos ]] && CMAKE_ARCH=(-DCMAKE_OSX_ARCHITECTURES="$ARCH")
cmake -G Ninja -S "$NATIVE" -B "$OUT/shim-build" "${CMAKE_ARCH[@]}" \
  -DCMAKE_BUILD_TYPE=Release -DREMLARK_DEPS_PREFIX="$PREFIX" >/dev/null
cmake --build "$OUT/shim-build" -j"$JOBS"
cp "$OUT/shim-build/$LIBNAME" "$OUT/$LIBNAME"
mkdir -p "$ROOT/build/native/$PLATFORM"
cp "$OUT/$LIBNAME" "$ROOT/build/native/$PLATFORM/$LIBNAME"
echo "==> $ROOT/build/native/$PLATFORM/$LIBNAME"
