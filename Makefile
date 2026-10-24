# Remlark 构建脚本
# 注意：Flutter 不支持桌面端交叉编译，mac / linux / windows 目标需在对应系统上执行。

APP_NAME   := remlark
DIST_DIR   := dist
SERVER_DIR := server
WINDOWS_ARCH = $(if $(filter ARM64 arm64,$(PROCESSOR_ARCHITECTURE)),arm64,x64)
LINUX_ARCH = $(if $(filter aarch64 arm64,$(shell uname -m)),arm64,x64)

ifeq ($(OS),Windows_NT)
  CURRENT := windows
else
  UNAME_S := $(shell uname -s)
  ifeq ($(UNAME_S),Darwin)
    CURRENT := mac
  else
    CURRENT := linux
  endif
endif

.PHONY: guard-mac guard-linux guard-windows guard-run all build mac linux windows run deps gen test analyze server server-run clean rdp-lib crypto-lib native-lib rdp-test-server test-platform

# 默认：按当前平台打包
all: build

build: $(CURRENT)

deps:
	flutter pub get
	cd $(SERVER_DIR) && dart pub get

# 生成 drift ORM 代码
gen: deps
	dart run build_runner build --delete-conflicting-outputs
	cd $(SERVER_DIR) && dart run build_runner build --delete-conflicting-outputs

# RDP 原生库（FreeRDP + OpenSSL 静态编译，首次约需 10 分钟，之后增量）
# macOS 同时编译 x86_64 与 arm64，以便打出通用二进制应用
rdp-lib:
ifeq ($(CURRENT),mac)
	native/rdp/scripts/build.sh x86_64
	native/rdp/scripts/build.sh arm64
else ifeq ($(CURRENT),linux)
	native/rdp/scripts/build.sh
else
	powershell -NoProfile -ExecutionPolicy Bypass -File native/rdp/scripts/build.ps1
endif

# SSH 加密原生库（OpenSSL AES-GCM，复用 rdp-lib 编译的 OpenSSL）
crypto-lib: rdp-lib
ifeq ($(CURRENT),mac)
	native/ssh_crypto/scripts/build.sh x86_64
	native/ssh_crypto/scripts/build.sh arm64
else ifeq ($(CURRENT),linux)
	native/ssh_crypto/scripts/build.sh
else
	powershell -NoProfile -ExecutionPolicy Bypass -File native/ssh_crypto/scripts/build.ps1
endif

# 全部原生库
native-lib: rdp-lib crypto-lib

# RDP 端到端测试用的服务端（FreeRDP 示例服务端 + 剪贴板测试服务端，不随应用打包）
rdp-test-server:
	native/rdp/scripts/build_test_server.sh

# 在耗时依赖准备前先检查，Flutter 包装入口在实际构建前还会复查一次。
guard-mac:
	python3 tools/utils/app_version.py guard macos

guard-linux:
	python3 tools/utils/app_version.py guard linux

guard-windows:
	python3 tools/utils/app_version.py guard windows

guard-run: guard-$(CURRENT)

# macOS：生成 .app 并打包为 zip
mac: guard-mac deps native-lib
	python3 tools/utils/app_version.py flutter build macos --release
	mkdir -p $(DIST_DIR)
	cd build/macos/Build/Products/Release && ditto -c -k --keepParent $(APP_NAME).app ../../../../../$(DIST_DIR)/$(APP_NAME)-macos.zip
	@echo "输出：$(DIST_DIR)/$(APP_NAME)-macos.zip"

# Linux：生成 Debian 安装包与便携 tar.gz，按主机架构选择 Flutter 输出目录
linux: guard-linux deps native-lib
	python3 tools/utils/app_version.py flutter build linux --release
	python3 linux/packaging/build.py --arch $(LINUX_ARCH) --output "$(DIST_DIR)"

# Windows：生成安装向导 exe 与便携 zip（需要 Inno Setup 6.5+）
windows: guard-windows deps native-lib
	python3 tools/utils/app_version.py flutter build windows --release
	powershell -NoProfile -ExecutionPolicy Bypass -File windows/packaging/build.ps1 -Arch $(WINDOWS_ARCH) -OutputDir "$(DIST_DIR)"

# 运行当前程序（当前平台）
run: guard-run deps native-lib
ifeq ($(CURRENT),mac)
	python3 tools/utils/app_version.py flutter run -d macos
else ifeq ($(CURRENT),linux)
	python3 tools/utils/app_version.py flutter run -d linux
else
	python3 tools/utils/app_version.py flutter run -d windows
endif

analyze:
	flutter analyze
	cd $(SERVER_DIR) && dart analyze

test:
	flutter test
	cd $(SERVER_DIR) && dart test

# 多平台单元测试（见 docs/multi-platform-testing.md），在 macOS / Linux / Windows 上分别执行
test-platform:
	flutter test test/platform

# 同步服务端：编译为可执行文件包（含 sqlite 动态库）
server: deps
	mkdir -p $(DIST_DIR)
	cd $(SERVER_DIR) && dart build cli -t bin/server.dart -o ../$(DIST_DIR)/remlark-sync-server
	@echo "输出：$(DIST_DIR)/remlark-sync-server/bundle/bin/server（用法：--port 8443 --token <令牌> [--cert cert.pem --key key.pem]）"

# 本地运行同步服务端（开发用），令牌通过 TOKEN 变量传入：make server-run TOKEN=xxx
server-run:
	cd $(SERVER_DIR) && dart run bin/server.dart --port 8443 --token $(TOKEN) --db data/remlark-sync.sqlite

clean:
	python3 tools/utils/app_version.py guard all
	flutter clean
	rm -rf $(DIST_DIR)

# 从品牌母版重新导出平台图标（仅更新图标时需要 Python 3 与 Pillow）。
.PHONY: icons
icons:
	python3 tools/branding/generate_icons.py
