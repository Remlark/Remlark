#!/usr/bin/env bash
# 在 Windows 上用 MSVC 编译 FFmpeg（静态，/MT），由 build.ps1 通过 MSYS2 bash 调用：
#   FFmpeg 的 configure 是 shell 脚本，需要 MSYS2 提供 bash / make；编译器仍是当前 VS 开发者环境中的 cl.exe。
# 只保留 H.264 解码器、解析器与 swscale，开启 D3D11VA / DXVA2 硬件解码。
# 用法：build_ffmpeg_msvc.sh <FFmpeg 源码目录> <编译目录> <安装前缀> <x86_64|arm64>
set -euo pipefail

SRC="$(cygpath -u "$1")"
BUILD="$(cygpath -u "$2")"
PREFIX="$(cygpath -m "$3")"
ARCH="$4"

# MSVC 的 link.exe 必须排在 MSYS2 自带的 /usr/bin/link 之前
CL_DIR="$(dirname "$(command -v cl.exe)")"
export PATH="$CL_DIR:/usr/bin:$PATH"

FF_ARCH=()
case "$ARCH" in
  x86_64) FF_ARCH=(--arch=x86_64) ;;
  # ARM64 的 MSVC 汇编需要 gas-preprocessor，这里关闭汇编；画面解码主要由 D3D11VA 硬件完成
  arm64) FF_ARCH=(--enable-cross-compile --target-os=win32 --arch=aarch64 --disable-asm) ;;
  *) echo "unsupported arch $ARCH"; exit 1 ;;
esac

rm -rf "$BUILD" && mkdir -p "$BUILD" && cd "$BUILD"
"$SRC/configure" --toolchain=msvc "${FF_ARCH[@]}" --prefix="$PREFIX" --extra-cflags=-MT \
  --enable-static --disable-shared --disable-debug --disable-doc \
  --disable-programs --disable-autodetect --disable-everything --disable-network \
  --disable-avdevice --disable-avformat --disable-avfilter --disable-swresample \
  --enable-decoder=h264 --enable-parser=h264 --enable-d3d11va --enable-dxva2 \
  --enable-hwaccel=h264_d3d11va,h264_d3d11va2,h264_dxva2 >ffmpeg-configure.log
make -j"$(nproc)" >ffmpeg-build.log
make install >/dev/null
