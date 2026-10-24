#!/usr/bin/env bash
# 在 Windows 上用 MSVC 编译 FFmpeg（静态，/MT），由 build.ps1 通过 MSYS2 bash 调用：
#   FFmpeg 的 configure 是 shell 脚本，需要 MSYS2 提供 bash / make；编译器仍是当前 VS 开发者环境中的 cl.exe。
# 只保留 H.264 解码器、解析器与 swscale，开启 D3D11VA / DXVA2 硬件解码。
# 用法：build_ffmpeg_msvc.sh <FFmpeg 源码目录> <编译目录> <安装前缀> <x86_64|arm64>
set -euo pipefail

# 普通 PowerShell 直接启动 bash 时不会加载 MSYS2 profile，先加入工具路径再调用 cygpath。
export PATH="/usr/bin:$PATH"
# CL 保存 MSVC 编译选项（如 /FS），禁止 MSYS2 将它们当作 Unix 路径转换。
export MSYS2_ENV_CONV_EXCL="${MSYS2_ENV_CONV_EXCL:+$MSYS2_ENV_CONV_EXCL;}CL"
# FFmpeg 通过英文版本输出识别 MSVC；中文 VS 输出会使其误用通用编译器参数。
export VSLANG=1033

# 同一份预检查既可在 OpenSSL 编译前单独调用，也在实际 FFmpeg 编译时执行。
for tool in cygpath make diff grep sed awk cl.exe; do
  command -v "$tool" >/dev/null || { echo "Missing FFmpeg build tool: $tool" >&2; exit 1; }
done

# MSVC 的 link.exe 必须排在 MSYS2 自带的 /usr/bin/link 之前
CL_DIR="$(dirname "$(command -v cl.exe)")"
export PATH="$CL_DIR:/usr/bin:$PATH"

# 仅安装中文资源时 VSLANG 不生效；提前提示安装英文包，避免 configure 误判编译器。
CL_BANNER="$(cl.exe 2>&1 || true)"
if ! grep -q '^Microsoft' <<<"$CL_BANNER"; then
  echo "FFmpeg requires the Visual Studio English language pack (en-US); install it with Visual Studio Installer." >&2
  exit 1
fi
if [[ "${1:-}" == --check-toolchain ]]; then
  exit 0
fi

SRC="$(cygpath -u "$1")"
BUILD="$(cygpath -u "$2")"
PREFIX="$(cygpath -m "$3")"
ARCH="$4"

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
