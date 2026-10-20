#!/usr/bin/env bash
# 编译 SSH 加密原生库（macOS / Linux）：libremlark_crypto，静态链接 OpenSSL。
# OpenSSL 复用 RDP 原生库构建产物（build/native/<平台-架构>/prefix），需先执行 native/rdp/scripts/build.sh
# 用法：native/ssh_crypto/scripts/build.sh [arch]   arch 默认当前架构
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../../.." && pwd)"
NATIVE="$ROOT/native/ssh_crypto"
OS="$(uname -s)"
ARCH="${1:-$(uname -m)}"
JOBS="$(getconf _NPROCESSORS_ONLN 2>/dev/null || echo 4)"
export MACOSX_DEPLOYMENT_TARGET=12.0

case "$OS" in
  Darwin) PLATFORM=macos; LIBNAME=libremlark_crypto.dylib ;;
  Linux) PLATFORM=linux; LIBNAME=libremlark_crypto.so ;;
  *) echo "unsupported OS: $OS (Windows 请使用 build.ps1)"; exit 1 ;;
esac

OUT="$ROOT/build/native/$PLATFORM-$ARCH"
PREFIX="$OUT/prefix"
if [[ ! -f "$PREFIX/lib/libcrypto.a" ]]; then
  echo "缺少 $PREFIX/lib/libcrypto.a，请先编译 RDP 原生库（make rdp-lib）"
  exit 1
fi

CMAKE_ARCH=()
[[ "$PLATFORM" == macos ]] && CMAKE_ARCH=(-DCMAKE_OSX_ARCHITECTURES="$ARCH")
cmake -G Ninja -S "$NATIVE" -B "$OUT/crypto-build" "${CMAKE_ARCH[@]}" \
  -DCMAKE_BUILD_TYPE=Release -DREMLARK_DEPS_PREFIX="$PREFIX" >/dev/null
cmake --build "$OUT/crypto-build" -j"$JOBS"
cp "$OUT/crypto-build/$LIBNAME" "$OUT/$LIBNAME"
echo "==> $OUT/$LIBNAME"
