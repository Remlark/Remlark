# 编译环境与打包

Remlark 是 Flutter 桌面应用，支持 macOS、Windows、Linux。桌面应用必须在目标操作系统上编译，不能在 Windows 上构建 macOS / Linux 应用。同步服务端使用 Dart，单独编译。

## 通用要求

- Flutter stable，包含 Dart SDK。当前项目 `pubspec.yaml` 要求 Dart `^3.13.5`；本轮验证使用 Flutter **3.47.7 / Dart 3.13.5**。
- Git；使用 Makefile 时还需要 GNU Make，本轮 Windows 使用 **4.4.1**，仅通过 Windows PowerShell 入口开发运行时不需要 Make。原生库还需要 CMake、Ninja、Perl；Windows x64 的 OpenSSL 汇编需要 NASM。
- 网络需能访问 Flutter / pub 依赖、GitHub、zlib.net。只有验证 dsh 真实安装时还需要 nodejs.org、registry.npmjs.org。
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
| Visual Studio 2022 | 安装“使用 C++ 的桌面开发”，包括 MSVC v143、Windows SDK、C++ CMake 工具；本轮 VS 17.14 / MSVC 14.44 |
| GNU Make | 使用 Makefile 时需要 `make.exe`；仅通过 `windows/run.ps1` 开发运行时不需要。Git Bash 自身不保证包含 Make |
| CMake / Ninja | 可使用 VS 自带版本；本轮 VS CMake 3.31.6；应能在开发者终端中直接执行 |
| Strawberry Perl | 使用原生 Windows Perl，不能使用 Git / MSYS 的 Perl 替代 OpenSSL 的 Windows 构建环境 |
| NASM | x64 OpenSSL 汇编所需，确保 `nasm.exe` 在 PATH 中 |
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
| `dist/remlark-1.0.0-windows-x64-setup.exe` | 安装向导；文件名版本来自 `pubspec.yaml`，不是固定写死 |
| `dist/remlark-windows-x64.zip` | 便携包；解压整个目录后运行 `remlark.exe` |
| `dist/remlark-sync-server/bundle/` | 同步服务端；需整体分发，`bin/server.exe` 依赖随包的 sqlite DLL |
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

Makefile 按 Windows 主机选择 x64 / arm64，安装器通过 `-Arch` 选择相同目标；不能混用 arm64 原生库和 x64 Flutter 输出。ARM64 实机验证见 M-16。安装包暂未配置代码签名；正式签名需要发布方证书。

### 已固定的原生构建约定

- `native/rdp/scripts/build.ps1` 固定 OpenSSL 3.6.5、FreeRDP 3.32.2、zlib 1.3.1，静态链接依赖；`native/ssh_crypto/scripts/build.ps1` 复用同一 OpenSSL。
- 明确使用当前 VS 目标架构的 MSVC，并关闭 FreeRDP 自动探测 ccache，避免误用 MinGW 工具链。
- PowerShell 脚本使用 UTF-8 BOM，C / C++ 使用 `/utf-8`；外部编译命令返回非零时立即终止。
- 安装器打包前检查 RDP、SSH 加密、sqlite、Flutter 引擎、AOT 与 VC++ 运行库；缺少任何必需项都会报错。

### 常见问题

| 现象 | 处理 |
| --- | --- |
| 找不到 `cl` / `nmake`，或目标架构不一致 | 重新进入 VS x64 开发者终端，确认 `VSCMD_ARG_TGT_ARCH=x64` |
| OpenSSL Configure 失败 | 检查 `perl -v` 为原生 Windows Strawberry Perl，`nasm -v` 可运行 |
| 找不到 Inno Setup | 安装 6.5+ 或指定 `ISCC`；它是 `ISCC.exe` 的完整路径，不是目录 |
| 找不到 VC++ x64 runtime | 在 VS 开发者终端打包，或将 `VC_REDIST_DIR` 指向包含三项 DLL 的 CRT 目录 |
| `C4819`、PowerShell 中文解析错误 | 保留项目的 UTF-8 / BOM 设置，不要转换为系统 ANSI 编码 |
| 无法删除 `build/native_assets/windows/*.dll` | 结束占用该文件的本项目测试或应用进程，再顺序运行构建 |
| 更换编译器后 CMake 缓存冲突 | 退出当前构建，保留旧目录并改名后重新构建；不要复用 MinGW 的 CMake 缓存 |

## macOS

准备 Xcode（含 Command Line Tools）、Flutter、GNU Make，以及原生构建依赖 CMake、Ninja、Perl、zlib。可使用系统工具及 Homebrew 安装的依赖；首次 Xcode 使用需完成许可确认与工具初始化，`flutter doctor -v` 应能识别 Xcode。

```bash
xcode-select -p
flutter doctor -v
make deps
make test-platform
make mac
make server
```

`make mac` 为原生库分别构建 x86_64 / arm64，然后编译 Flutter macOS Release，并输出 `dist/remlark-macos.zip`。当前文档已有 macOS x86_64 验证记录，arm64 的实机功能及发布签名、公证需另行验证与配置。

## Linux（Ubuntu / Debian）

本轮使用 **Ubuntu 26.04 LTS x86_64、Flutter 3.47.7 / Dart 3.13.5、Clang 21.1.8、GCC 15.2.0、CMake 4.2.3、Ninja 1.13.2、GTK 3.24.52、dpkg-deb 1.23.7**。原生依赖固定为 OpenSSL 3.6.5 / FreeRDP 3.32.2，源码由构建脚本下载，静态链接进 RDP / SSH 胶水库。源码构建需要 GitHub 网络访问；Flutter / pub 依赖也需要网络。

### 安装构建与测试依赖

```bash
sudo apt-get update
sudo apt-get install -y build-essential clang cmake ninja-build pkg-config \
  libgtk-3-dev libstdc++-15-dev libsecret-1-dev fonts-noto-cjk perl zlib1g-dev \
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

### 产物与安装

| 产物 | 说明 |
| --- | --- |
| `dist/remlark-1.0.0-linux-amd64.deb` | Ubuntu / Debian x64 安装包，版本从 pubspec.yaml 读取 |
| `dist/remlark-linux-x64.tar.gz` | 便携包，必须解压并保留整个 bundle |
| `build/linux/x64/release/bundle/` | Flutter 原始 Release 输出 |
| `dist/remlark-sync-server/bundle/` | 同步服务端，需整体分发 |

```bash
sudo apt install ./dist/remlark-1.0.0-linux-amd64.deb
remlark
# 卸载程序；应用数据保存在用户目录，不由包管理器删除。
sudo apt remove remlark

# 或使用便携包：
tar -xzf dist/remlark-linux-x64.tar.gz
./bundle/remlark
python3 bundle/install-desktop.py  # 可选：为当前用户安装菜单入口与图标
```

Debian 包将程序安装到 `/opt/remlark`，命令入口为 `/usr/bin/remlark`，菜单与图标安装到 `/usr/share`。无需在用户机器安装 Flutter 或编译工具，但需要包中 Depends 声明的系统运行库。Depends 根据构建机器上的 ELF 库生成，因此应在支持的最旧发行版上构建；本轮 Ubuntu 26.04 产物不声明兼容更早的 Ubuntu。

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

服务端产物位于 `dist/remlark-sync-server/bundle/`；Windows 使用 `bin/server.exe`，macOS / Linux 使用 `bin/server`。从该 bundle 运行 `--help` 查看参数。开发时可执行 `make server-run TOKEN=<本地令牌>`，数据写入 `server/data/`。

截至 2026-10-21，Windows x64 验证：应用、RDP / SSH 原生库和同步服务端已编译通过；安装器编译、完整性验证与专项测试结果记录在 [multi-platform-testing.md](multi-platform-testing.md)。跨平台实机测试和安装、升级、卸载的交互检查按其中的手工清单执行。

Linux x64 本轮完成默认 `make`、原生库与同步服务端编译：全量测试 139 项通过 / 6 项按条件跳过，另行启用的 dsh 2 项通过，最终平台测试 28 项、服务端测试 2 项通过；静态检查、deb 解包和便携包本机图形启动、包内原生库与 APT 模拟安装验证通过。真实远程主机及干净系统安装 / 升级 / 卸载仍按手工清单验证，结果见 [multi-platform-testing.md](multi-platform-testing.md)。

## GitHub Actions 自动 Release

工作流为 `.github/workflows/release.yml`。先提交并推送代码，确认 `pubspec.yaml` 版本（忽略 `+` 后的构建号），再推送相同版本标签，例如：

```bash
git tag v1.0.0
git push origin v1.0.0
```

也可在 Actions → Desktop Release → Run workflow 中指定已有标签重试。手工运行仍按标签检出，不会将分支新代码混入旧版本。

固定 Flutter 3.47.7，从官方源码标签启动 SDK，以便 ARM64 runner 下载原生 Dart SDK。Linux 使用 Ubuntu 24.04（x64 / arm64）及发行版配套 C++ 库，Windows 使用 windows-2022 / windows-11-arm、MSVC、原生 Perl、NASM 和 Inno Setup，macOS 使用 macos-15，构建双架构原生库和通用 app。每个任务运行 `make test-platform`；所有构建通过后统一上传 10 个安装 / 便携附件及 SHA256SUMS，并公开 Release。失败时保留构建日志，发布任务不会执行。

Windows ARM64 自动选择匹配架构的 CRT 和安装器；手工可执行 `make windows WINDOWS_ARCH=arm64`，必须在原生 ARM64 Windows 与对应 VS 环境运行。打包脚本支持 `-Arch arm64`。macOS DMG 包含应用与 Applications 入口，通用 zip 同时保留。安装包目前未配置签名 / 公证，仍需 M-16 实机验证。

Release CI 额外固定 FreeRDP `USE_VERSION_FROM_GIT_TAG=OFF`，防止读取应用标签后生成错误的 ABI 库名。Windows 构建步骤使用原生 PowerShell，源码解压显式调用系统 tar，避免 Git Bash 工具覆盖系统命令。

Windows 测试还需要 Python 3（GitHub runner 已提供），用于生成包含中文文件名的标准 PAX 测试夹具；应用运行不需要 Python。GNU Make 调用 NMake 时会暂时清除 MAKEFLAGS 并恢复，避免 GNU 长参数污染 OpenSSL 构建。

Windows 应用解压使用 archive 4.5.2 的流式接口，在独立 isolate 处理大包，规避 ARM64 系统 tar 的 Unicode 缺陷；这是新增依赖，原有锁定版本未升级。CRT 按架构校验：x64 要求 FH4 的 vcruntime140_1.dll，ARM64 不要求；附带目标架构完整 CRT 目录。

CI 同时支持 VS 2022 / VS 2026，从 VCToolsRedistDir 的目标架构目录匹配 Microsoft.VC*.CRT。Windows 安装 JOM 并行编译 OpenSSL（MSVC 显式 `/FS` 同步 PDB 写入），安装阶段固定串行 NMake，避免依赖 Makefile 并发改写；本地没有 JOM 时编译也回退 NMake。原生库按 runner、CPU 与 native 源码哈希缓存；原生编译完成后即使后续打包失败也保存，工具链重大升级时递增工作流缓存前缀。
