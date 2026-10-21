#!/usr/bin/env bash
# 编译 FreeRDP 示例服务端（仅用于端到端测试，不随应用打包）
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../../.." && pwd)"
ARCH="$(uname -m)"
OS="$(uname -s | tr '[:upper:]' '[:lower:]')"; [[ "$OS" == darwin ]] && OS=macos
OUT="$ROOT/build/native/$OS-$ARCH"
PREFIX="$OUT/prefix"
SRC="$ROOT/native/rdp/.deps/FreeRDP-3.32.2"
# 清理旧版配置缓存中的系统 OpenSSL 元数据，保证库与 pkg-config 都来自项目依赖。
cmake -G Ninja -U '*OPENSSL*' -S "$SRC" -B "$OUT/test-server-build" -DCMAKE_BUILD_TYPE=Release \
  -DCMAKE_PREFIX_PATH="$PREFIX" -DWITH_SYSTEMD=OFF \
  -DOPENSSL_ROOT_DIR="$PREFIX" -DOPENSSL_USE_STATIC_LIBS=ON -DBUILD_SHARED_LIBS=OFF \
  -DWITH_SERVER=ON -DWITH_SAMPLE=ON -DWITH_SHADOW=OFF -DWITH_PROXY=OFF -DWITH_PLATFORM_SERVER=OFF \
  -DWITH_CLIENT=OFF -DWITH_CLIENT_SDL=OFF -DWITH_X11=OFF -DWITH_WAYLAND=OFF -DWITH_FFMPEG=OFF -DWITH_SWSCALE=OFF \
  -DWITH_JSON_DISABLED=ON -DWITH_AAD=OFF -DWITH_KRB5=OFF -DWITH_FUSE=OFF -DWITH_PCSC=OFF -DWITH_CUPS=OFF \
  -DWITH_PULSE=OFF -DWITH_ALSA=OFF -DWITH_OSS=OFF -DWITH_OPUS=OFF -DWITH_URIPARSER=OFF -DWITH_MANPAGES=OFF \
  -DWITH_WINPR_TOOLS=ON -DWITH_UNICODE_BUILTIN=ON -DWITH_INTERNAL_MD4=ON -DWITH_INTERNAL_RC4=ON -DWITH_INTERNAL_MD5=ON \
  -DCHANNEL_URBDRC=OFF >"$OUT/test-server-configure.log"
cmake --build "$OUT/test-server-build" -j"$(getconf _NPROCESSORS_ONLN)" --target sfreerdp-server >"$OUT/test-server-build.log"
find "$OUT/test-server-build" -name sfreerdp-server -type f -perm -u+x | head -1

# 剪贴板测试服务端（native/rdp/test/clip_test_server.c）
B="$OUT/test-server-build"
EXTRA_LIBS=(-lm -lz)
[[ "$OS" == macos ]] && EXTRA_LIBS+=(-framework CoreFoundation -framework Security -framework IOKit -framework SystemConfiguration -framework CoreServices -framework AudioToolbox -framework CoreAudio -framework AVFoundation -framework CoreMedia -framework Foundation -framework Carbon -framework AppKit)
cc -O1 -o "$OUT/clip_test_server" "$ROOT/native/rdp/test/clip_test_server.c" \
  -I"$SRC/include" -I"$B/include" -I"$SRC/winpr/include" -I"$B/winpr/include" \
  "$B/server/common/libfreerdp-server3.a" "$B/libfreerdp/libfreerdp3.a" \
  "$B/channels/rdpsnd/common/librdpsnd-common.a" "$B/channels/remdesk/common/libremdesk-common.a" \
  "$B/winpr/libwinpr/libwinpr3.a" "$PREFIX/lib/libssl.a" "$PREFIX/lib/libcrypto.a" "${EXTRA_LIBS[@]}"
echo "$OUT/clip_test_server"
