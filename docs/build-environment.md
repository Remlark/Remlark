# 编译环境与打包

Remlark 是 Flutter 桌面应用，支持 macOS、Windows、Linux。桌面应用必须在目标操作系统上编译，不能在 Windows 上构建 macOS / Linux 应用。同步服务端使用 Dart，单独编译。

## 通用要求

- Flutter stable，包含 Dart SDK。当前项目 `pubspec.yaml` 要求 Dart `^3.13.5`；本轮验证使用 Flutter **3.47.7 / Dart 3.13.5**。
- Git；使用 Makefile 时还需要 GNU Make，本轮 Windows 使用 **4.4.1**，仅通过 Windows PowerShell 入口开发运行时不需要 Make。原生库还需要 CMake、Ninja、Perl；Windows x64 的 OpenSSL 汇编需要 NASM。
- Python 3.9+（命令 `python3`）：版本工具及三平台原生源码下载校验使用标准库，不需要额外 Python 包。
- 网络需能访问 Flutter / pub 依赖、GitHub、zlib.net、ffmpeg.org。只有验证 dsh 真实安装时还需要 nodejs.org、registry.npmjs.org。
- 保留仓库中的 `pubspec.lock` 与 `server/pubspec.lock`，日常构建使用 `pub get`，不要为解决构建问题直接升级依赖。

在仓库根目录执行：

```text
flutter --version
flutter doctor -v
make deps
make test-platform
make test
make analyze
```

`make test` 包含客户端与服务端测试；真实服务端、原生库或网络依赖未准备好时，部分端到端测试会跳过。具体条件与手工测试见 [multi-platform-testing.md](multi-platform-testing.md)。同一工作区的 Flutter 测试和构建应顺序执行，Windows 下并行运行可能占用共享的 native assets DLL。

原生源码下载通过 `tools/utils/source_archive.py` 统一处理：每个来源最多尝试 3 次，60 秒网络超时，完整校验 gzip CRC、tar 目录和预期版本根目录，通过后原子替换压缩包，再调用各平台 tar 解压。无效响应不会直接进入编译。Windows zlib 1.3.1 优先使用[官方 GitHub 发布](https://github.com/madler/zlib/releases/tag/v1.3.1)，备用 zlib.net fossils，两个来源均验证固定 SHA-256 `9a93b2b7dfdac77ceba5a558a580e74667dd6fede4585b91eefb60f03b72df23`。Windows 先下载并校验尚需编译的 zlib / FFmpeg，再编译 OpenSSL，避免网络异常在耗时编译之后才暴露。

源码包验证通过后可直接复用；瞬时错误在同一任务中退避重试，永久 HTTP 错误尝试镜像，本地磁盘/权限错误立即失败。每次响应另有 180 秒流传输预算（阻塞读取仍受 60 秒 socket 超时约束）。源码解压到同目录临时位置，关键文件齐全后写 `.remlark-source.json` 并替换正式目录；只存在目录但没有完成记录不算准备成功，解压/发布失败不会留下可复用的半目录。

原生依赖每个阶段安装成功后在 `build/native/<平台-架构>/.completed/` 记录必需产物摘要及构建配方。复用时检查所有必需库和头文件，重建时先移除本阶段旧输出；不要手工补写完成记录。Windows 在下载前检查工具和实际 cl 目标架构，FFmpeg 的 MSYS2 / 英文资源检查也提前；POSIX 检查系统开发依赖。工具缺失应在耗时 OpenSSL 编译前报错。

## Windows x64

### 没有 Make 时如何运行

Windows 不自带 GNU Make。开发运行可以直接使用仓库自带的 PowerShell 入口，在仓库根目录执行：

```powershell
Set-Location C:\Code\Remlark
powershell -NoProfile -ExecutionPolicy Bypass -File .\windows\run.ps1
```

它会准备 Flutter 依赖，缺少 RDP / SSH 加密 DLL 时编译原生库，然后执行 `flutter run -d windows`。已有完整原生库时跳过原生编译；首次原生构建会自动查找并初始化 VS x64 开发者环境，但仍需将原生 Windows Perl、NASM 等工具加入 PATH。运行结束按 Flutter 提示使用 `q` 退出。

```powershell
# 修改 native/ 下的代码后，显式重编译原生库再启动。
powershell -NoProfile -ExecutionPolicy Bypass -File .\windows\run.ps1 -RebuildNative
# 只准备依赖与原生库，不启动图形界面。
powershell -NoProfile -ExecutionPolicy Bypass -File .\windows\run.ps1 -PrepareOnly
```

只想使用应用时，运行 `dist/` 中的 setup 安装程序即可，不需要 Flutter、Visual Studio 或 Make。

### 安装工具

| 工具 | 要求与作用 |
| --- | --- |
| Windows | 本轮在 Windows 11 25H2 x64 验证；安装器最低设置 Windows 10，Windows 10 尚未实机验证 |
| Flutter | 将 Flutter 的 `bin` 加入 PATH；Dart 使用同一 Flutter SDK 自带版本 |
| Visual Studio 2022 | 安装“使用 C++ 的桌面开发”，包括 MSVC v143、Windows SDK、C++ CMake 工具与 English（en-US）语言包（FFmpeg 识别编译器所需）；本轮 VS 17.14 / MSVC 14.44 |
| GNU Make | 使用 Makefile 时需要 `make.exe`；仅通过 `windows/run.ps1` 开发运行时不需要。Git Bash 自身不保证包含 Make |
| CMake / Ninja | 可使用 VS 自带版本；本轮 VS CMake 3.31.6；应能在开发者终端中直接执行 |
| Strawberry Perl | 使用原生 Windows Perl，不能使用 Git / MSYS 的 Perl 替代 OpenSSL 的 Windows 构建环境 |
| NASM | x64 OpenSSL / FFmpeg 汇编所需，确保 `nasm.exe` 在 PATH 中 |
| MSYS2 | 只用来运行 FFmpeg 的 configure（编译器仍是 MSVC）；默认 `C:\msys64`，其他位置用 `MSYS2_ROOT` 指定；安装后在 MSYS2 终端执行 `pacman -S --needed make diffutils` |
| Inno Setup | **6.5 或以上**，本轮使用 6.7.3；`ISCC.exe` 编译安装向导 |

官方入口：[Flutter Windows 环境](https://docs.flutter.dev/platform-integration/windows/setup)、[Visual Studio](https://visualstudio.microsoft.com/downloads/)、[Strawberry Perl](https://strawberryperl.com/)、[NASM](https://www.nasm.us/)、[Inno Setup](https://jrsoftware.org/isdl.php)。Android SDK、Android Studio 和 Chrome 不是 Windows 桌面构建的必要依赖。

### 打开 x64 开发者终端

使用开始菜单的 **Developer PowerShell for VS 2022**，选择 x64 目标；也可以在 PowerShell 中按实际安装位置执行：

```powershell
& 'C:\Program Files\Microsoft Visual Studio\2022\Community\Common7\Tools\Launch-VsDevShell.ps1' -Arch amd64 -HostArch amd64 -SkipAutomaticLocation
Set-Location C:\Code\Remlark

Get-Command flutter, dart, make, cl, nmake, cmake, ninja, perl, nasm
$env:VSCMD_ARG_TGT_ARCH  # 应为 x64
flutter doctor -v
```

Visual Studio 为 Professional / Enterprise 或安装在其他位置时，相应替换路径。单个 PowerShell 进程不允许执行脚本时，可通过 `powershell -NoProfile -ExecutionPolicy Bypass -File <脚本路径>` 调用项目脚本；不需要修改系统全局执行策略。

如果工具使用便携目录，**仅在当前终端**补充 PATH，例如：

```powershell
$env:Path = 'C:\Tools\Strawberry\perl\bin;C:\Tools\NASM;C:\Tools\Make\bin;' + $env:Path
# 非标准位置的 Inno Setup 需要显式指定完整路径。
$env:ISCC = 'C:\Tools\Inno Setup 6\ISCC.exe'
```

Inno Setup 编译器查找顺序：`ISCC` 环境变量 → PATH 中的 `ISCC.exe` → Program Files 下的 `Inno Setup 6`。

### 编译与生成安装包

```powershell
make deps
make test-platform
make native-lib
flutter test test/native_crypto_test.dart
make windows  # Windows 下直接 make 也执行同一目标
make server
```

首次原生编译需要下载并编译 OpenSSL、FreeRDP、zlib，可能持续十几分钟或更久，后续按缓存增量构建。`make windows` 自动包含依赖准备与原生编译，无须每次单独执行 `make native-lib`。

| 产物 | 说明 |
| --- | --- |
| `dist/Remlark-1.0.0-windows-x64-setup.exe` | 安装向导；文件名版本来自 `VERSION`，不是固定写死 |
| `dist/Remlark-windows-x64.zip` | 便携包；解压整个目录后运行 `Remlark.exe` |
| `dist/Remlark-sync-server/bundle/` | 同步服务端；需整体分发，`bin/server.exe` 依赖随包的 sqlite DLL |
| `build/windows/x64/runner/Release/` | Flutter 原始 Release 输出 |
| `build/native/windows-x86_64/` | 原生库、依赖与编译缓存 |
| `build/packaging/windows-x64-<标识>/` | 每次打包的独立暂存目录 |

安装器默认写入 `%LOCALAPPDATA%\Programs\Remlark`，不要求管理员权限，提供中英文向导、开始菜单入口及可选桌面快捷方式。相同 AppId 用于覆盖升级，卸载保留应用数据目录中的数据库、密钥与日志。不要随发布版本变更安装脚本中的 AppId。

安装包和便携包都会附带 `msvcp140.dll`、`vcruntime140.dll`、`vcruntime140_1.dll`，采用 [Flutter 官方说明中的应用本地运行库分发方式](https://docs.flutter.dev/platform-integration/windows/building#building-your-own-zip-file-for-windows)，不需要在用户机器安装编译工具。打包默认从开发者终端的 `VCToolsRedistDir\x64\Microsoft.VC143.CRT` 获取；也可显式指定：

```powershell
$env:VC_REDIST_DIR = 'C:\Program Files\Microsoft Visual Studio\2022\Community\VC\Redist\MSVC\<实际版本>\x64\Microsoft.VC143.CRT'
```

已有完整 Release 时，只重新打包：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File windows/packaging/build.ps1
# 可选：-ReleaseDir <目录> -OutputDir <目录> -CompilerPath <ISCC.exe> -RuntimeDir <CRT目录>
```

Windows 桌面端只发布 x64（2026-10-26 起不再支持 ARM64，Windows 11 ARM 设备可仿真运行 x64 版）。`make windows` 固定打 x64 包，在 ARM64 主机上由 guard-windows 直接停止；打包脚本只接受 `-Arch x64`。原生库脚本仍保留 arm64 参数，仅供 ARM 主机本地 `flutter run` 开发，未验证。安装包暂未配置代码签名；正式签名需要发布方证书。

### 已固定的原生构建约定

- `native/rdp/scripts/build.ps1` 固定 OpenSSL 3.6.5、FFmpeg 8.1.3、FreeRDP 3.32.2、zlib 1.3.1，静态链接依赖；FFmpeg 只含 H.264 解码器与 D3D11VA / DXVA2 硬件解码，由 `build_ffmpeg_msvc.sh` 在 MSYS2 bash 中用 MSVC（/MT）编译，ARM64 关闭汇编；`native/ssh_crypto/scripts/build.ps1` 复用同一 OpenSSL。
- FFmpeg 的 MSVC 检测依赖英文版本输出，Visual Studio Installer 的语言包中需同时安装 English（en-US）；脚本设置 `VSLANG=1033`，缺少英文资源时提前报错。普通 PowerShell 直接调用 MSYS2 bash 时，脚本先加入 `/usr/bin` 再转换路径，并禁止将 `CL` 中的 `/FS` 等编译选项转换成路径。
- FFmpeg 的 MSVC 静态库直接生成为 `avcodec.lib` / `swscale.lib` / `avutil.lib`，构建脚本检查三项产物，不使用 MinGW 的 `libxxx.a` 命名规则。
- FreeRDP 3.32.2 的 H.264 硬解错误标签位于块末尾，MSVC C11 会报 C2143；Windows 构建脚本自动为 `fail_hwdevice_create` 补空语句，重复运行不会重复修改。
- 明确使用当前 VS 目标架构的 MSVC，并关闭 FreeRDP 自动探测 ccache，避免误用 MinGW 工具链。
- PowerShell 脚本使用 UTF-8 BOM，C / C++ 使用 `/utf-8`；外部编译命令返回非零时立即终止。
- 安装器打包前检查 RDP、SSH 加密、sqlite、Flutter 引擎、AOT 与 VC++ 运行库；缺少任何必需项都会报错。

### 常见问题

| 现象 | 处理 |
| --- | --- |
| 找不到 `cl` / `nmake`，或目标架构不一致 | 重新进入 VS x64 开发者终端，确认 `VSCMD_ARG_TGT_ARCH=x64` |
| 未找到 MSYS2 或 FFmpeg configure 失败 | 安装 MSYS2 并执行 `pacman -S --needed make diffutils`，或用 `MSYS2_ROOT` 指定目录；查看 `build\native\windows-<架构>\ffmpeg-build\ffmpeg-configure.log` 与同目录的 `ffbuild/config.log` |
| FFmpeg 提示缺少 English language pack，或误报 MSVC 版本不支持 | 在 Visual Studio Installer → 修改 → 语言包中安装 English（en-US），保留现有中文包；重新运行原生构建 |
| OpenSSL Configure 失败 | 检查 `perl -v` 为原生 Windows Strawberry Perl，`nasm -v` 可运行 |
| 找不到 Inno Setup | 安装 6.5+ 或指定 `ISCC`；它是 `ISCC.exe` 的完整路径，不是目录 |
| 找不到 VC++ x64 runtime | 在 VS 开发者终端打包，或将 `VC_REDIST_DIR` 指向包含三项 DLL 的 CRT 目录 |
| `C4819`、PowerShell 中文解析错误 | 保留项目的 UTF-8 / BOM 设置，不要转换为系统 ANSI 编码 |
| 无法删除 `build/native_assets/windows/*.dll` | 结束占用该文件的本项目测试或应用进程，再顺序运行构建 |
| 更换编译器后 CMake 缓存冲突 | 退出当前构建，保留旧目录并改名后重新构建；不要复用 MinGW 的 CMake 缓存 |

## macOS

准备 Xcode（含 Command Line Tools）、Flutter、GNU Make，以及原生构建依赖 CMake、Ninja、Perl、zlib、NASM（x86_64 FFmpeg 汇编，`brew install nasm`）。可使用系统工具及 Homebrew 安装的依赖；首次 Xcode 使用需完成许可确认与工具初始化，`flutter doctor -v` 应能识别 Xcode。

```bash
xcode-select -p
flutter doctor -v
make deps
make test-platform
make mac
make server
```

`make mac` 为原生库分别构建 x86_64 / arm64，然后编译 Flutter macOS Release，并输出 `dist/Remlark-macos.zip`。当前文档已有 macOS x86_64 验证记录，arm64 的实机功能及发布签名、公证需另行验证与配置。

## Linux（Ubuntu / Debian）

本轮使用 **Ubuntu 26.04 LTS x86_64、Flutter 3.47.7 / Dart 3.13.5、Clang 21.1.8、GCC 15.2.0、CMake 4.2.3、Ninja 1.13.2、GTK 3.24.52、dpkg-deb 1.23.7**。原生依赖固定为 OpenSSL 3.6.5 / FFmpeg 8.1.3 / FreeRDP 3.32.2，源码由构建脚本下载，静态链接进 RDP / SSH 胶水库。源码构建需要 GitHub 网络访问；Flutter / pub 依赖也需要网络。

### 安装构建与测试依赖

```bash
sudo apt-get update
sudo apt-get install -y build-essential clang cmake ninja-build pkg-config \
  libgtk-3-dev libstdc++-15-dev libsecret-1-dev fonts-noto-cjk perl zlib1g-dev nasm libva-dev \
  curl ca-certificates tar zip unzip xdg-utils python3 dpkg-dev \
  openssh-server xvfb xdotool desktop-file-utils
```

`libstdc++-15-dev` 对应本轮 Ubuntu 的 GCC 版本，其他发行版应使用配套的 libstdc++ 开发包。`openssh-server` 用于本地 SSH / SFTP 端到端测试，`xvfb` / `xdotool` 用于图形冒烟测试，`dpkg-dev` 提供根据 ELF 实际依赖生成 Debian 包 Depends 的 `dpkg-shlibdeps`。GTK 与 libsecret 开发包也是 Flutter 插件编译依赖，`fonts-noto-cjk` 用于中文显示与真实字体布局测试。

Flutter SDK 可放在用户目录，无须 root。本轮位置为 `~/.local/opt/flutter`。全新机器可安装本轮验证的 SDK：

```bash
mkdir -p "$HOME/.local/opt"
curl -fL --retry 3 \
  https://storage.googleapis.com/flutter_infra_release/releases/stable/linux/flutter_linux_3.47.7-stable.tar.xz \
  -o /tmp/flutter_linux_3.47.7-stable.tar.xz
tar -xJf /tmp/flutter_linux_3.47.7-stable.tar.xz -C "$HOME/.local/opt"
```

本机已将 SDK 的 PATH 配置写入 `~/.bashrc` 和 `~/.profile`，新开的 Bash 终端会自动生效。已打开的终端不会自动刷新环境，先执行下面的 `export` 即可继续使用 `make run`。其他机器安装 SDK 后也需要配置 PATH：

```bash
export PATH="$HOME/.local/opt/flutter/bin:$PATH"
flutter --version
flutter doctor -v
make deps
make native-lib
make rdp-test-server
make test-platform
make test
RMK_DSH_E2E=1 flutter test test/dsh_install_e2e_test.dart
make analyze
make linux  # Linux 下直接 make 也执行同一目标
make server
```

Flutter 测试与 Flutter 应用构建顺序执行，保留锁文件，不执行依赖升级。首次原生库编译较慢，后续复用 `build/native/linux-x86_64/` 中的缓存。图形运行使用当前桌面会话；无桌面 CI 可用 `xvfb-run`，但系统文件选择器、拖放、真实远程主机等仍需手工验证。

2026-10-21 H.264 补验时，本机缺少 NASM 与 libva 开发文件，且当前终端不能免密 sudo；通过 `apt-get download nasm libva-dev` 下载发行版包，解包到忽略的 `build/linux-test-deps/root/`，沿用系统已安装的 libva 运行库。该工作区后续编译先执行 `source build/validation/linux-h264-env.sh`，仅对当前终端补充 PATH、pkg-config、头文件及链接路径；其他机器推荐按上面的 apt 命令安装完整系统依赖。执行 `make clean` 会移除这些本地工具与环境脚本，届时需重新准备依赖。本机只有虚拟显示设备，没有 DRM 渲染节点，因此本轮可验证 H.264 软件解码及硬件不可用时的回退，实际 VAAPI GPU 解码仍需支持的显卡、驱动与渲染节点权限。

### 产物与安装

| 产物 | 说明 |
| --- | --- |
| `dist/Remlark-1.0.0-linux-amd64.deb` | Ubuntu / Debian x64 安装包，版本从 VERSION 读取 |
| `dist/Remlark-linux-x64.tar.gz` | 便携包，必须解压并保留整个 bundle |
| `build/linux/x64/release/bundle/` | Flutter 原始 Release 输出 |
| `dist/Remlark-sync-server/bundle/` | 同步服务端，需整体分发 |

```bash
sudo apt install ./dist/Remlark-1.0.0-linux-amd64.deb
Remlark
# 卸载程序；应用数据保存在用户目录，不由包管理器删除。
sudo apt remove remlark

# 或使用便携包：
tar -xzf dist/Remlark-linux-x64.tar.gz
./bundle/Remlark
python3 bundle/install-desktop.py  # 可选：为当前用户安装菜单入口与图标
```

Debian 包将程序安装到 `/opt/remlark`，命令入口为 `/usr/bin/Remlark`，菜单与图标安装到 `/usr/share`。无需在用户机器安装 Flutter 或编译工具，但需要包中 Depends 声明的系统运行库。Depends 根据构建机器上的 ELF 库生成，因此应在支持的最旧发行版上构建；本轮 Ubuntu 26.04 产物不声明兼容更早的 Ubuntu。

Linux CMake 关闭 Android 间接依赖带来的可选 JNI 插件，避免链接构建机的 Java 绝对路径。构建和运行 Linux 应用均不需要 JDK / JRE。

已有完整 Release 时，可以单独重新打包：

```bash
python3 linux/packaging/build.py --arch x64
```

打包前检查 Flutter 引擎、AOT、sqlite、RDP / SSH 原生库及桌面资源；缺少必需组件会立即报错。Linux arm64 的 Makefile 使用 Flutter `arm64` 输出目录、Debian `arm64` 包架构，原生库继续使用 `linux-aarch64` 目录；本轮只验证 x64，arm64 仍需实机验证。

## 生成代码与服务端

修改 drift ORM 表结构或需重建生成代码时执行 `make gen`。数据库查询与索引约束见仓库开发规范。

```text
make server
```

服务端产物位于 `dist/Remlark-sync-server/bundle/`；Windows 使用 `bin/server.exe`，macOS / Linux 使用 `bin/server`。从该 bundle 运行 `--help` 查看参数。开发时可执行 `make server-run TOKEN=<本地令牌>`，数据写入 `server/data/`。

Release CI 另有独立的服务端六路构建：macOS / Windows / Linux 各 x64、arm64，固定 Dart 3.13.5，仅安装 `server/pubspec.lock` 中的依赖，执行服务端静态检查和测试后用 `dart build cli` 编译。macOS x64 使用 `macos-15-intel`，arm64 优先使用自托管 Mac mini、离线时使用 `macos-15`，分别输出，桌面客户端继续使用 universal。

服务端附件为 `Remlark-sync-server-<版本>-<系统>-<架构>.tar.gz`（macOS / Linux）或 `.zip`（Windows），压缩包内保留完整 `bundle/`。本地已有服务端构建时，可执行 `python3 tools/release/server_bundle.py macos x64 --smoke` 打包并在临时目录解压、启动、读写 SQLite；平台与架构必须匹配实际构建。六个 CI 任务均执行此验证，主程序或 SQLite 库缺失、架构不符、启动/读写失败时终止发布。

截至 2026-10-21，Windows x64 验证：应用、RDP / SSH 原生库和同步服务端已编译通过；安装器编译、完整性验证与专项测试结果记录在 [multi-platform-testing.md](multi-platform-testing.md)。跨平台实机测试和安装、升级、卸载的交互检查按其中的手工清单执行。

Linux x64 本轮完成默认 `make`、原生库与同步服务端编译：全量测试 139 项通过 / 6 项按条件跳过，另行启用的 dsh 2 项通过，最终平台测试 28 项、服务端测试 2 项通过；静态检查、deb 解包和便携包本机图形启动、包内原生库与 APT 模拟安装验证通过。真实远程主机及干净系统安装 / 升级 / 卸载仍按手工清单验证，结果见 [multi-platform-testing.md](multi-platform-testing.md)。

## GitHub Actions 自动 Release

工作流为 `.github/workflows/release.yml`。先提交并推送代码，确认根目录 `VERSION` 版本（忽略 `+` 后的构建号），再推送相同版本标签，例如：

```bash
git tag v1.0.0
git push origin v1.0.0
```

也可在 Actions → Desktop Release → Run workflow 中指定已有标签重试。手工运行仍按标签检出，不会将分支新代码混入旧版本。

### 使用自托管 Mac mini 构建 macOS

Release 的 macOS 桌面包（universal）与服务端 arm64 会优先使用自托管 Mac mini，离线时自动回退 GitHub 的 `macos-15`；服务端 x64 仍使用 `macos-15-intel`。配置步骤：

1. Mac mini 安装完整 Xcode（`sudo xcode-select -s /Applications/Xcode.app` 并接受许可）、Homebrew 与 Python 3；cmake / ninja / nasm 及 Flutter 由工作流安装。
2. 在测试仓库（当前为 zhy2006/remlark，仓库级）或组织的 Settings → Actions → Runners 新建 macOS ARM64 runner，配置时添加自定义标签 `remlark-macmini`。将要公开的 Remlark/Remlark 不注册自托管 runner、不配置令牌，始终使用托管 runner；组织级 runner 位于 Default 组时，公开仓库需勾选 Allow public repositories 才能使用，不要为 Remlark 开启。用 `./svc.sh install && ./svc.sh start` 安装为当前用户的 LaunchAgent（不要装成系统 LaunchDaemon，否则 codesign 无法访问用户钥匙串），并开启自动登录、关闭睡眠。runner 的 `.path` 需包含 Homebrew 路径（`/opt/homebrew/bin`）。
3. 创建 fine-grained PAT 保存为仓库 Secret `RUNNER_STATUS_TOKEN`：组织级 runner 需组织权限 Self-hosted runners 只读（Resource owner 选组织）；仓库级 runner 需该仓库 Administration 只读。选择脚本先查仓库接口再查组织接口，任一处在线即使用；某个接口无权限或不存在（个人账号）只记警告。未配置时始终回退托管 runner。
4. 公开仓库须限制自托管 runner：Settings → Actions → General 设为外部贡献者 PR 运行前需批准；组织仓库建议把 runner 放进只允许 `release.yml` 使用的 runner group，防止 fork PR 修改工作流在本机执行代码。

自托管 runner 的 `RUNNER_TEMP` 和工作区每个任务都会清空，Release 改由 `tools/utils/flutter_sdk.py` 把 Flutter 安装到 `RUNNER_TOOL_CACHE/flutter/<版本>`（runner 目录下 `_work/_tool`），克隆完成写 `<版本>.complete` 标记，后续任务直接复用 SDK 与已下载的 Dart / 引擎缓存；无标记的半成品重新克隆，升级 Flutter 版本时删除旧版本。托管 runner 仍每次克隆到 `RUNNER_TEMP`。

一台 Mac mini 默认只注册一个 runner，桌面包和服务端 arm64 会排队顺序执行。选择任务判定在线后 runner 恰好掉线时，任务会一直排队，需要取消后重跑以回退托管 runner。

固定 Flutter 3.47.7，从官方源码标签启动 SDK，以便 ARM64 runner 下载原生 Dart SDK。Linux 使用 Ubuntu 24.04（x64 / arm64）及发行版配套 C++ 库，Windows 桌面使用 windows-2022（仅 x64）、MSVC、原生 Perl、NASM 和 Inno Setup，macOS 使用 macos-15，构建双架构原生库和通用 app。桌面四路任务运行 `make test-platform`；服务端独立六路构建（含 windows-11-arm）。所有构建通过后统一上传 8 个桌面附件、6 个服务端附件及 SHA256SUMS，并公开 Release。构建失败时发布任务不会执行，错误信息查看 Actions 执行日志，不额外上传日志压缩包。

Windows 安装包附带 x64 CRT（含 FH4 的 vcruntime140_1.dll），安装器 `x64compatible` 允许在 Windows 11 ARM64 上安装。macOS DMG 包含应用与 Applications 入口，通用 zip 同时保留。macOS CI 已接入固定自签证书（未公证），Windows 安装包仍未签名；需 M-16 / M-20 实机验证。

Release CI 额外固定 FreeRDP `USE_VERSION_FROM_GIT_TAG=OFF`，防止读取应用标签后生成错误的 ABI 库名。Windows 构建步骤使用原生 PowerShell，源码解压显式调用系统 tar，避免 Git Bash 工具覆盖系统命令。

Windows 测试还需要 Python 3（GitHub runner 已提供），用于生成包含中文文件名的标准 PAX 测试夹具；应用运行不需要 Python。GNU Make 调用 NMake 时会暂时清除 MAKEFLAGS 并恢复，避免 GNU 长参数污染 OpenSSL 构建。

Windows 应用解压使用 archive 4.5.2 的流式接口，在独立 isolate 处理大包，规避 ARM64 系统 tar 的 Unicode 缺陷；这是新增依赖，原有锁定版本未升级。CRT 按架构校验：x64 要求 FH4 的 vcruntime140_1.dll，ARM64 不要求；附带目标架构完整 CRT 目录。

CI 同时支持 VS 2022 / VS 2026，从 VCToolsRedistDir 的目标架构目录匹配 Microsoft.VC*.CRT。Windows 安装 JOM 并行编译 OpenSSL（MSVC 显式 `/FS` 同步 PDB 写入），安装阶段固定串行 NMake，避免依赖 Makefile 并发改写；本地没有 JOM 时编译也回退 NMake。

原生缓存分两层：完整库缓存 `native-v2` 绑定 runner、CPU、native 源码哈希，以及工作区/校验器/MSVC 环境身份；阶段缓存 `native-progress-v1` 绑定同环境下的第三方构建配方，以 run_id/run_attempt 后缀保存新进度，并只从同配方前缀恢复。后续阶段普通失败时，已经完成的 OpenSSL、zlib、FFmpeg 等依赖和已验证压缩包仍保存；修改胶水 C 源码不作废第三方阶段缓存，修改依赖构建脚本或工具链则需要重新验证/构建。完整缓存要求 RDP、SSH 和全部依赖均有有效完成记录，macOS 通用包要验证两个架构。缓存只保留安装前缀、记录和成品库，不保存大型临时构建目录；测试与发布恢复完整缓存使用相同路径集合。全局强制取消或 runner 故障可能使保存步骤无法执行。

已验证发布：[v1.0.0](https://github.com/Remlark/Remlark/releases/tag/v1.0.0)，[构建记录](https://github.com/Remlark/Remlark/actions/runs/39593809838)。后续先修改 VERSION 的版本、提交并推送，再创建同版本 v* 标签；不要复用已发布标签。

### 发布前只跑平台专项测试

独立工作流 `.github/workflows/test.yml`（Platform Tests）由 `test*` 标签触发，也可通过 Run workflow 手动运行。提交待测修改后，为该提交创建一个新的测试标签并推送，例如：

```bash
git tag test-20261025-01
git push origin test-20261025-01
```

每次修改后使用新标签；工作流检出触发标签对应的提交，标签不要求匹配 VERSION。测试标签不会触发 `v*` Release 工作流。

测试矩阵覆盖 macOS / Linux 各 x64、arm64 与 Windows x64，共五路（Windows ARM64 桌面已不支持）。每路使用与 Release 相同的 Flutter 3.47.7，仅按锁文件安装客户端测试依赖，每路只执行一次 `make test-platform`，不运行客户端全量、服务端或真实 dsh 安装测试，也不安装服务端依赖；某个平台失败不会取消其他平台。每路超时上限为 20 分钟。

本流程不执行应用、安装包、服务端可执行文件或 RDP/SSH 原生库的产品构建，不上传 artifacts，不读取发布签名凭据或发布 Release。测试执行本身仍会生成 Dart 测试程序、SQLite 测试资产及小型 C/Swift 测试夹具，这些属于运行测试的必要步骤。

原生相关测试只复用与 runner / 架构 / native 源码哈希完全匹配的 Release 原生缓存；macOS ARM64 复用包含双架构的 universal 缓存，Intel 没有对应缓存时不使用其他 runner 的缓存。命中后强制要求 RDP 原生库可加载，未命中时在 Actions Summary 明确记录，依赖原生库及本地 RDP 测试服务端的用例按已有条件跳过；不会为了测试临时编译原生依赖。需要指定真实远端凭据的 RDP 测试和按需截图默认仍跳过。正式发布仍保留构建后的原生测试门禁，测试工作流通过不代表安装包验证通过。

### 仅验证 GitHub Actions 编译

在 Desktop Release 中选择 Run workflow，选择待验证分支，tag 留空并保持 `build_only=true`。工作流执行桌面四路构建、安装包生成与构建前后 `make test-platform`，以及服务端六路构建、测试与解包启动验证，不上传 Actions artifacts、不发布 Release。正式手工发布需填写与 VERSION 中版本号一致的已有版本标签，并关闭 `build_only`；推送 v* 标签仍自动发布。

正式发布所需的压缩包仅作为任务间中转上传，保留 7 天，重跑同名包时覆盖。只有 `publish` 成功（附件已全部进入 Release）后，`cleanup` 任务才删除**本次运行**的 `packages-*`、`logs-*`；任一构建或发布失败都不删除，已成功平台的包保留，可直接 Re-run failed jobs。历史运行的中转包不自动清理，由 7 天保留期过期或手动删除。Release 附件和原生缓存不受影响。清理使用 `actions: write`，API 失败会明确报错。

CI 中的网络安装（Flutter 克隆和首次初始化、apt-get、brew、choco、MSYS2 pacman、pub get、gh release upload/edit）统一通过 `python3 tools/utils/retry_command.py [--clean 路径] -- 命令...` 有限重试，默认 3 次、间隔 10/20 秒，最终返回最后一次退出码。

sqlite3 构建钩子从 `github.com/.../releases/download` 下载预编译库且不检查 HTTP 状态，该入口返回 5xx 时会报“Hash of downloaded file … is bef140a1…”（即 504 错误页的哈希），重试无法绕过持续故障。CI 在 pub get 后、首次测试前执行 `python3 tools/utils/sqlite_assets.py <项目> --os <系统> --arch <架构|universal>`：经 GitHub API 资产接口（失败回退普通下载地址）取得文件、校验 sha256 后放入 `.dart_tool/hooks_runner/shared/sqlite3/build/download-<哈希前 8 位>/`，钩子发现哈希一致便直接复用。本地遇到同样错误也可手动执行该命令。

2026-10-21 已用此模式完成硬件加速版本五路验证：[Desktop Build #11](https://github.com/Remlark/Remlark/actions/runs/39615318096)，macOS universal、Windows / Linux x64 与 arm64 编译、打包、构建后平台测试全部通过。具体解码结果和实机验证范围见 [multi-platform-testing.md](multi-platform-testing.md#2026-10-21-硬件加速版本-github-actions-全矩阵验证step-84)。


## 修改版本与编译

只修改根目录 `VERSION`，例如 `1.2.3+4`：版本号为 `1.2.3`，构建号为 `4`，对应 Release 标签 `v1.2.3`。默认保留 `1.0.0+1`。不要向 pubspec 添加版本，也不要在编译命令中另行覆盖版本。

```bash
python3 tools/utils/app_version.py json
make                   # 当前平台正式应用与安装包
make run               # 开发运行，注入 Dart 版本
# 需要手工调用 Flutter build 时也通过相同入口：
python3 tools/utils/app_version.py flutter build macos --release
```

手工编译时将 macos 替换为当前平台的 windows / linux。工具从脚本所在仓库读取 VERSION，支持路径包含中文、空格及 CRLF。缺失或无效版本立即报错。Flutter build 的数字版本与构建号用于系统元数据；预发布标识保留在 Dart 完整版本、发布标签和安装包名称中，Debian 元数据用 `~` 表示预发布。Flutter run 没有 build-name / build-number 参数，开发运行只注入 Dart 版本，系统元数据使用 Flutter 默认值；分发请使用 make 或上述 build 入口。

修改 VERSION 后重新编译再打包；macOS DMG 和 Windows 安装器会拒绝元数据不匹配的旧应用。Windows 独立开发入口也需要 PATH 中存在 Python 3（`python3`），与打包及 CI 使用相同解析器。


### macOS CI 自签证书

在仓库 Settings → Secrets and variables → Actions → Secrets 配置：

| Secret | 内容 |
| --- | --- |
| `MACOS_CERTIFICATE_BASE64` | 包含私钥的 P12 的 Base64，可用 `base64 < remlark-signing.p12 | tr -d '\r\n' | pbcopy` 复制 |
| `MACOS_CERTIFICATE_PASSWORD` | 导出 P12 的非空密码 |

只需要上述两个 Secrets。CI 自动从专用钥匙串读取唯一代码签名身份，并生成临时钥匙串密码；旧的 `MACOS_SIGNING_IDENTITY` / `MACOS_KEYCHAIN_PASSWORD` 已不再使用，可以删除。P12 必须包含一个带私钥的代码签名身份，缺失或多个身份均在导入后明确报错。

证书使用钥匙串访问 → 证书助理 → 创建证书，类型选择自签名根证书 / 代码签名；从“我的证书”导出带私钥的 `.p12`。所有版本复用同一证书及私钥，离线备份，不提交到仓库。

Release CI 在 macOS 编译前检查配置并导入临时钥匙串，保存并临时更新钥匙串搜索列表，不修改证书信任设置。编译后按由内到外顺序重签嵌套二进制和 App，使用 Release.entitlements，严格验证全部架构；再重建 zip / DMG 并签 DMG。导入、签名、验证任何一步失败即阻止发布；始终清理临时钥匙串并还原搜索列表。Windows / Linux 打包和平台测试仍走原有入口。

本地 `make mac` 仍使用原有临时签名；GitHub 自签不包含 Apple 公证，也不保证 Gatekeeper 或隐私权限免重新授权。真实下载与升级按 M-20 测试。


## 构建前的运行实例保护

桌面打包与运行请使用 `make` / `make mac` / `make linux` / `make windows` / `make run`；Windows 也可使用 `windows/run.ps1`。这些入口以及 `make clean` 会先检查项目输出目录中是否有运行中的 Remlark，存在时停止并提示 PID 与路径，请正常退出后重试。保护不会关闭应用或断开连接，已安装应用和其他检出目录不受影响。

需要直接传递 Flutter 构建参数时，使用带版本与保护的包装入口，例如 `python3 tools/utils/app_version.py flutter build macos --debug`。直接调用 Flutter 命令会绕过此检查；构建期间不要重新启动同一路径的应用。运行中的原生库文件被覆盖后，Dart 惰性加载可能把 SQLite 再加载一次，在退出时产生 SIGSEGV，详见设计文档 Step 100/101 与多平台测试 M-26。
