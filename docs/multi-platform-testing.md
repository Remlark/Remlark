# 多平台测试

Remlark 是 Flutter 桌面应用，支持 macOS、Windows、Linux 三个平台。Flutter 桌面不能交叉编译，各平台的构建和测试都要在对应系统上执行。macOS（x86_64）、Windows x64 和 Linux x64 已有自动化验证记录；真实远程主机、干净机器安装等项目仍需按本文逐项验证。

本文列出：

1. 哪些功能和平台有关、各平台用的是什么实现；
2. 用来检查这些功能的单元测试（编号 P-xx）；
3. 依赖本机环境的端到端测试，以及各平台的准备步骤；
4. 自动化测试覆盖不到、需要手工验证的项目（编号 M-xx）；
5. 已经发现的平台问题。

## 维护规则

- 新增或修改与平台有关的功能时（`Platform.isXxx`、`defaultTargetPlatform`、`Process.run`/`Process.start` 调用系统命令、FFI 原生库、MethodChannel、平台工程目录 `macos/` `windows/` `linux/` 下的原生代码、按平台区分的快捷键或路径），必须同时完成以下三件事：
  1. 在[平台差异总览](#1-平台差异总览)中加一行或更新对应行；
  2. 在 `test/platform/` 下加单元测试（或扩展已有测试），给测试分配新的 P 编号，文件头注释写上“多平台测试 P-xx”，并登记到[单元测试](#2-单元测试test-platform)表中；
  3. 自动化测不到的部分（界面交互、系统对话框、真实安装包等）写进[手工测试清单](#4-手工测试清单)。
- 平台实现遵循 agents.md 的约定：先定义接口，每个平台各自实现；改一个平台时三个平台一起改，对应的 P 测试也要一起改。
- 平台相关的单元测试要能在三个平台上都跑：
  - 纯逻辑部分（包名、路径布局、按键映射）直接构造各平台的实现类来测，与当前系统无关；
  - 依赖当前系统的部分用 `Platform.isXxx` 分支写出各平台的预期结果，不要直接跳过。
- 在某个平台上完成一轮验证后，更新[验证记录](#6-验证记录)。

## 1. 平台差异总览

| 功能 | 代码位置 | macOS | Windows | Linux | 单元测试 | 手工 |
| --- | --- | --- | --- | --- | --- | --- |
| Codex 运行包 | [lib/modules/ai/codex/platform/](../lib/modules/ai/codex/platform/) | `*-apple-darwin.tar.gz` | `*-pc-windows-msvc.tar.gz`，文件名带 `.exe` | `*-unknown-linux-musl.tar.gz` | P-01 | M-08 |
| dsh 私有 Node.js | [lib/modules/ai/dsh/platform/](../lib/modules/ai/dsh/platform/) | `darwin-*.tar.gz`，`bin/node` | `win-*.zip`，根目录 `node.exe`，PATH 分隔符 `;` | `linux-*.tar.gz`，`bin/node` | P-02 | M-09 |
| 压缩包解压 | [lib/utils/archive/](../lib/utils/archive/) | `tar` / `unzip` | Dart 流式解压 tar.gz / zip，独立 isolate，不依赖系统 tar | `tar` / `unzip` | P-03 | M-08、M-09 |
| 主目录、PATH 查找 | [lib/utils/platform_utils.dart](../lib/utils/platform_utils.dart) | `HOME`；额外查找 Homebrew 目录 | `USERPROFILE`；依次补 `.exe` `.bat` `.cmd` 后缀 | `HOME` | P-04 | — |
| 打开文件管理器、浏览器 | [lib/utils/platform_utils.dart](../lib/utils/platform_utils.dart) | `open` | `explorer`、`rundll32 url.dll,FileProtocolHandler` | `xdg-open` | — | M-10 |
| 主密钥、凭据目录权限 | [lib/utils/file_permissions/](../lib/utils/file_permissions/)，调用方 `secret_store.dart`、Codex / dsh 的 HOME 目录 | `chmod 600/700` | `icacls /inheritance:r /grant:r <用户>:F`（目录加 `(OI)(CI)`） | `chmod 600/700` | P-04 | M-01 |
| 应用数据目录 | `path_provider` | `~/Library/Application Support/<bundle id>` | `%APPDATA%\<公司>\<产品>` | `~/.local/share/<应用 id>` | — | M-01 |
| VNC 延迟文件剪贴板 | [lazy_file_clipboard.dart](../lib/modules/remote_desktop/vnc/lazy_file_clipboard.dart) + [MainFlutterWindow.swift](../macos/Runner/MainFlutterWindow.swift) | 原生 NSPasteboard，粘贴时才下载 | 不支持，复制时立即下载 | 不支持，复制时立即下载 | P-05 | M-06 |
| 系统免密登录快捷指令 | [install_system_key_action.dart](../lib/modules/snippets/actions/install_system_key_action.dart) | 可用 | 不可用，列表中隐藏 | 可用 | P-05 | M-11 |
| RDP Command 键映射 | [rdp_scancode.dart](../lib/modules/remote_desktop/rdp/rdp_scancode.dart)、[rdp_session.dart](../lib/modules/remote_desktop/rdp/rdp_session.dart) | ⌘ 映射为 Ctrl | Win 键保持 Win | Win 键保持 Win | P-05 | M-05 |
| 聊天发送快捷键 | [chat_panel.dart](../lib/modules/ai/ui/chat_panel.dart) | ⌘Enter | Ctrl+Enter | Ctrl+Enter | [chat_send_key_test.dart](../test/chat_send_key_test.dart) | M-07 |
| 终端复制粘贴快捷键、字体 | [terminal_pane.dart](../lib/modules/terminal/ui/terminal_pane.dart) | ⌘C / ⌘V / ⌘A，Menlo | Ctrl+Shift+C / V，Ctrl+Insert，monospace | 同 Windows | — | M-03 |
| SFTP 多选 | [file_pane.dart](../lib/modules/sftp/ui/file_pane.dart) | ⌘ 或 Ctrl 点击 | Ctrl 点击 | Ctrl 点击 | — | M-04 |
| 剪贴板文件读取、拖放 | `pasteboard`、`desktop_drop`、`file_selector` 插件 | 插件实现 | 插件实现 | 插件实现 | [file_drop_target_test.dart](../test/file_drop_target_test.dart)（只测分发逻辑） | M-03、M-04、M-06 |
| 窗口默认尺寸 / 最小尺寸 | [window_config.dart](../lib/app/window_config.dart) + 三个平台的 runner | `MainFlutterWindow.swift` | `main.cpp`、`flutter_window.cpp`（按 DPI 换算） | `my_application.cc` | P-06 | M-02 |
| 原生库（RDP、SSH AES-GCM） | [hook/build.dart](../hook/build.dart)、`native/*/scripts/` | `build.sh`，x86_64 + arm64，系统 zlib | `build.ps1 [-Arch x86_64\|arm64]`，按 VS 目标架构；显式 MSVC、静态 OpenSSL / zlib，关闭自动 ccache | `build.sh`（`aarch64` 命名），系统 zlib | P-06、[native_crypto_test.dart](../test/native_crypto_test.dart) | M-12 |
| 打包 | [Makefile](../Makefile)、[Windows 安装器](../windows/packaging/) | `make mac` → zip | `make windows` → Inno Setup 安装 exe + 便携 zip，附带应用本地 VC++ 运行库 | `make linux` → deb + tar.gz，按 x64 / arm64 输出；发布前检查原生库和资源 | P-06、P-08、P-09 | M-12、M-14 |
| 可选 JNI 依赖 | `linux/CMakeLists.txt`，Flutter 间接依赖 | 无 Linux JNI 插件 | 可选插件，未发现 JDK 时不构建 | 关闭 Android 间接依赖引入的可选 JNI，避免携带构建机 Java 绝对路径 | P-09 | M-12 |
| 开发启动 | [Makefile](../Makefile)、[Windows 启动脚本](../windows/run.ps1) | `make run` | `windows/run.ps1` 无须 Make，按需构建原生库；也支持 `make run` | `make run` | P-08 | M-15 |
| 应用图标 | `tools/branding/`、`linux/packaging/` | `.icns` | 7 帧 `.ico` | PNG + `.desktop` | — | M-12 |
| 同步服务端 | [server/](../server/) | `dart build cli` | 同左 | 同左 | `server/` 中的 `dart test` | M-13 |
| 源码编码与构建失败检查 | `windows/CMakeLists.txt`、`native/*/CMakeLists.txt`、`native/utils/windows_build.ps1` | UTF-8，shell 严格错误检查 | MSVC `/utf-8`；PowerShell 带 UTF-8 BOM，外部命令失败立即停止 | UTF-8，shell 严格错误检查 | P-06 | M-12 |
| 测试 Dart 子进程与日志关闭 | `test/helpers/platform_tools.dart`、`lib/utils/app_log.dart` | Dart 可执行文件；关闭日志释放句柄 | 定位 SDK 的 `dart.exe`；删除日志目录前关闭句柄 | 同 macOS | P-07 | M-01、M-13 |
| Release CI | `.github/workflows/release.yml`、`tools/release/` | Intel / Apple Silicon 通用 zip + DMG，lipo 校验 | x64 / arm64 安装 exe + zip；匹配 CRT 与 Inno 架构 | 原生 x64 / arm64 runner，deb + tar.gz | P-10、P-08、P-09 | M-16 |

## 2. 单元测试（test/platform）

运行方式：`make test-platform`（等价于 `flutter test test/platform`）。三个平台都要执行，测试会按当前系统检查对应的预期结果。

| 编号 | 测试文件 | 检查内容 | 关联功能 |
| --- | --- | --- | --- |
| P-01 | [codex_platform_test.dart](../test/platform/codex_platform_test.dart) | 三个平台、x64/arm64 的 Codex 发布包名称；Windows 可执行文件带 `.exe`；不支持的架构返回 null；`current()` 选中当前平台的实现且当前架构有发布包 | Codex 运行包 |
| P-02 | [dsh_platform_test.dart](../test/platform/dsh_platform_test.dart) | Node.js 安装包名称；`node` / `npm-cli.js` / PATH 目录的位置；PATH 分隔符；子进程环境只有一个 PATH 键（Windows 下键名为 `Path`），且私有 node 目录在最前面 | dsh 私有 Node.js |
| P-03 | [archive_extractor_test.dart](../test/platform/archive_extractor_test.dart) | `current()` 选中对应的解压实现；按平台实现解压 `.tar.gz` 和 `.zip`（Windows 的 Dart 解码同时在三个系统测试），中文文件名不乱码，POSIX 下保留可执行权限；压缩包损坏时抛出 `ProcessException` | 压缩包解压 |
| P-04 | [platform_utils_test.dart](../test/platform/platform_utils_test.dart) | 主目录是存在的绝对路径；`which` 能找到 `sh`（Windows 下为 `cmd.exe`），找不到时返回 null；`isUnixDesktop` 的值；权限实现按平台选择，icacls 参数正确；主密钥文件权限为 600、目录为 700，Windows 下 `icacls` 输出中有当前用户且没有继承的权限；`SecretStore` 加解密能往返 | 主目录、PATH、密钥权限 |
| P-05 | [platform_features_test.dart](../test/platform/platform_features_test.dart) | 延迟文件剪贴板只在 macOS 上可用；系统免密登录在 Windows 上不可用；RDP 中 ⌘ 映射为 Ctrl，Windows / Linux 下保持 Win 键 | 只在部分平台提供的功能、按键映射 |
| P-06 | [window_config_sync_test.dart](../test/platform/window_config_sync_test.dart) | 三个平台 runner 中的窗口尺寸与 `window_config.dart` 一致；构建钩子覆盖三个平台；每个原生库都有 `build.sh` 和 `build.ps1`，`build.ps1` 支持 x86_64 / arm64，输出目录与构建钩子一致；Makefile 有 mac / linux / windows / run 目标 | 窗口尺寸、原生库、打包 |
| P-07 | [runtime_lifecycle_test.dart](../test/platform/runtime_lifecycle_test.dart) | 实际启动 Dart 子进程；重新初始化后写入新日志目录，关闭后目录可删除 | 同步测试启动、日志句柄生命周期 |
| P-08 | [windows_packaging_test.dart](../test/platform/windows_packaging_test.dart) | 三平台打包与启动入口；Windows VS 2022 / 2026 CRT 查找、按架构运行库、当前用户安装、数据保留与 BOM；实际暂存应用和 VC++ 运行库，覆盖中文空格路径、缺少原生库 / CRT 时终止；无 Make 启动参数与 PowerShell 解析 | Windows 安装器、开发启动与分发完整性 |
| P-09 | [linux_packaging_test.dart](../test/platform/linux_packaging_test.dart) | 三平台保留独立打包入口；Linux x64 / arm64 架构命名；禁用无用 JNI；实际运行打包脚本，缺少原生库时立即终止；在中文、空格、引号、反斜线、% 等路径中实际注册桌面入口并用 GIO 启动 | Linux 安装器与分发完整性 |
| P-10 | [release_workflow_test.dart](../test/platform/release_workflow_test.dart) | 拒绝错误版本标签、缺失附件时阻止发布、完整双架构矩阵生成正确 SHA-256 清单 | 自动发布 |

P-06 同时检查 FreeRDP 禁用宿主仓库 Git 标签版本探测，以及 Windows 下载源码使用系统 tar，避免应用版本改变库名或 Git Bash tar 误解析盘符。

P-06 还检查 macOS / Linux 测试服务端与应用使用同一 OpenSSL 前缀、关闭 systemd 依赖，以及 Windows CMake 的 UTF-8 编译选项、PowerShell BOM 与实际解析，以及外部命令失败时的退出码；macOS / Linux 检查构建脚本严格错误处理。

其他测试中与平台有关的部分：

| 测试文件 | 平台相关内容 | 各平台情况 |
| --- | --- | --- |
| [chat_send_key_test.dart](../test/chat_send_key_test.dart) | ⌘Enter / Ctrl+Enter 的判断 | 纯逻辑，三个平台都能跑 |
| [native_crypto_test.dart](../test/native_crypto_test.dart) | 原生 AES-GCM 与纯 Dart 实现的结果一致 | 需要先 `make crypto-lib`；Windows / Linux 上未验证过 |
| [codex_installer_test.dart](../test/codex_installer_test.dart) | 安装、升级、校验失败时回滚 | 用脚本模拟 codex：macOS / Linux 为 sh，Windows 为 `.cmd`；压缩用系统 tar（Windows 为 System32 的 bsdtar） |
| [layout_overflow_test.dart](../test/layout_overflow_test.dart) | 最小窗口尺寸下界面不溢出 | 纯 Flutter，三个平台都能跑 |
| [ui_snapshot_test.dart](../test/ui_snapshot_test.dart) | 页面快照 | 字体渲染因平台而异，只在 macOS 上维护快照 |

## 3. 端到端测试与各平台准备

端到端测试依赖本机服务或预先编译的程序，条件不满足时会跳过。在 Windows / Linux 上验证时，要确认测试是真的执行了，不能只看“通过”——跳过的测试也会显示为通过（看输出中的 `skip` 和 `markTestSkipped` 信息）。

| 测试 | 依赖 | macOS | Windows | Linux |
| --- | --- | --- | --- | --- |
| [ssh_e2e_test.dart](../test/ssh_e2e_test.dart) | 本机 `/usr/sbin/sshd`、`ssh-keygen` | 可运行；剪贴板、Finder 相关用例只在 macOS 上执行 | 跳过（Windows 的 OpenSSH Server 需要管理员权限以服务方式运行），按 M-03、M-04 手工验证 | 安装 `openssh-server` 后可运行 |
| [rdp_e2e_test.dart](../test/rdp_e2e_test.dart) | `make rdp-lib` + `make rdp-test-server`、`openssl` | 可运行 | 没有测试服务端，跳过 | 可运行；目录按当前架构选择（arm64 为 `linux-aarch64`） |
| [rdp_clipboard_test.dart](../test/rdp_clipboard_test.dart) | 同上 | 可运行 | 跳过 | 可运行 |
| [dsh_install_e2e_test.dart](../test/dsh_install_e2e_test.dart) | 网络（nodejs.org、npm），`RMK_DSH_E2E=1` | 可运行 | 需要验证：zip 解压、`node.exe`、`Path` | 需要验证 |
| [sync_e2e_test.dart](../test/sync_e2e_test.dart) | 本机启动同步服务端 | 可运行 | 需要验证 | 需要验证 |

各平台的准备：

- **Windows**：Flutter + Visual Studio 2022（C++ 桌面开发）；编译原生库还需要 CMake、Ninja、Strawberry Perl、NASM，并在 “x64 Native Tools Command Prompt” 中执行 `make native-lib`；`make` 可以用 Git for Windows 或 MSYS2 自带的。确认 `C:\Windows\System32\tar.exe` 存在（Windows 10 1803 及以上自带）。
- **Linux**（以 Ubuntu 为例）：`clang cmake ninja-build pkg-config libgtk-3-dev`、`openssh-server`、`xdg-utils`、`zip unzip`；编译 FreeRDP 需要的开发包见 `native/rdp/scripts/build.sh`。

## 4. 手工测试清单

每一项都要在三个平台上分别执行。结果记录在[验证记录](#6-验证记录)中：✅ 通过，❌ 失败（附问题），— 不适用。

| 编号 | 项目 | 步骤与预期 |
| --- | --- | --- |
| M-01 | 首次启动与数据目录 | 全新环境启动 → 数据目录中生成数据库、`master.key`、日志目录（启动日志第一行写有系统版本）；重启后主机、密钥都还在 |
| M-02 | 窗口 | 默认 1280×820 并居中；不能缩小到 960×640 以下；Windows 上在 125% / 150% 缩放下最小尺寸正确；最小尺寸下各页面不溢出、不被截断；中英文切换后同样不溢出 |
| M-03 | 终端 | SSH 连接后可以输入；中文显示正常、字体等宽；复制 / 粘贴快捷键与右键菜单中显示的一致（macOS ⌘C/⌘V，其他平台 Ctrl+Shift+C/V、Ctrl+Insert）；在资源管理器 / 文件管理器中复制文件后，在终端里粘贴 → 显示“粘贴并上传”并上传成功；把文件拖进终端 → 上传成功；“选中即复制”有效 |
| M-04 | SFTP | 本地栏起始目录为用户主目录（Windows 为 `C:\Users\<用户名>`）；进入上级目录直到盘符根目录不出错；Ctrl 点击多选、Shift 连续选择；新建、重命名、删除本地文件；带中文和空格的文件名上传、下载正常；从系统文件管理器拖入文件即上传 |
| M-05 | RDP | 连接 Windows 服务器：画面、鼠标、键盘正常；macOS 上 ⌘C/⌘V 在远程中生效，Windows / Linux 上 Win 键打开远程开始菜单；剪贴板文本双向同步；本地复制文件后在远程粘贴、远程复制文件后在本地粘贴；拖放上传 |
| M-06 | VNC | 连接 macOS 屏幕共享与普通 VNC 服务器；远程复制文件后在本地粘贴：macOS 上粘贴时才下载，Windows / Linux 上复制时就下载，粘贴得到的是完整文件；修饰键不会卡住 |
| M-07 | AI 聊天 | 输入框提示的发送快捷键与平台一致；⌘Enter / Ctrl+Enter 发送，单独 Enter 换行 |
| M-08 | Codex 安装 | 设置中安装 Codex → 下载、校验、解压成功，显示版本号；登录、提问都正常；升级时正在运行的 Codex 被结束后完成替换（Windows 上文件被占用时，下次启动会清理旧目录）；卸载后登录信息保留 |
| M-09 | DeepSeek Harness 安装 | 安装私有 Node.js 与 dsh → 启动 ACP 进程并能提问；Windows 上 zip 解压后能找到 `node.exe`，npm 安装成功；卸载后会话记录保留 |
| M-10 | 打开外部程序 | 设置 → 数据中打开数据目录、RDP 中打开下载目录，都能打开系统文件管理器；Codex 登录能在默认浏览器中打开授权页面；导入 / 导出时系统文件选择对话框正常 |
| M-11 | 系统免密登录 | macOS / Linux：执行后 `~/.ssh` 下生成密钥，`~/.ssh/config` 写入别名，系统终端里 `ssh <别名>` 能免密登录；Windows：快捷指令列表中不显示这一项 |
| M-12 | 构建与打包 | `make native-lib` 编译成功；`make` 打出安装包；解压到新机器（没有装开发环境）上能启动；原生库被打进安装包（RDP 能连接，日志显示“已启用原生 AES-GCM 加密”）；应用图标在 Dock / 任务栏 / 桌面启动器中显示正确；Linux 的 deb 安装后菜单出现应用，命令入口可用，升级 / 卸载不删除用户数据；便携包解压后运行 `bundle/install-desktop.py`，菜单中出现应用 |
| M-13 | 同步服务端 | `make server` 编译成功；用 `--port --token` 启动；两个客户端同步主机与密钥 |
| M-14 | Windows 安装、升级与卸载 | Windows 10 / 11 x64 干净环境运行 setup；中英文向导、安装目录、开始菜单与可选桌面入口正确；启动不要求手工安装 VC++；关闭运行中的应用后覆盖升级；卸载程序及快捷方式移除，数据库、凭据与日志保留；macOS / Linux 不适用 |
| M-15 | Windows 无 Make 开发启动 | 未安装 Make、已有 Flutter 与 VS C++ 的 Windows x64 环境执行 `powershell -NoProfile -ExecutionPolicy Bypass -File windows/run.ps1`，缺少原生库时按文档准备 Perl / NASM 后可编译并启动；已有原生库时不重复编译；`-RebuildNative` 强制重编译；`-PrepareOnly` 不打开应用；macOS / Linux 按 `make run` 验证 |
| M-16 | Release 安装验证 | 在干净的 Windows / Linux x64、arm64 与 Intel / Apple Silicon macOS 下载附件，验证 SHA256SUMS，安装、启动、升级、卸载并连接 SSH / RDP；macOS DMG 拖入 Applications。当前没有签名 / 公证，CI 成功不代替实机交互验证 |

## 5. 已发现的平台问题

| 编号 | 平台 | 问题 | 建议 |
| --- | --- | --- | --- |
| K-01 | Windows | `ssh_e2e_test.dart` 在 `main()` 中读取 `Platform.environment['USER']!`，Windows 上没有这个变量，文件加载时就会报错，而不是跳过 | 已修复：用户名改用 `test/helpers/platform_tools.dart` 的 `currentUserName()`（Windows 下取 `USERNAME`）；Windows 上明确跳过并提示，SSH 按手工清单验证 |
| K-02 | Linux arm64 | `rdp_e2e_test.dart` 在非 macOS 上把架构写死为 `x86_64`，arm64 上找不到 `linux-aarch64` 下的测试服务端，测试被跳过 | 已修复：RDP 测试统一用 `nativeBuildFile()`，按当前 Dart 进程的 ABI 选择与构建钩子相同的目录 |
| K-03 | Windows | `PlatformUtils.restrictPermissions` 在 Windows 上什么都不做，`master.key` 和 Codex 凭据目录用的是默认 ACL | 已修复：新增 `FilePermissions` 接口（POSIX 用 chmod，Windows 用 icacls 去掉继承、只授权当前用户），P-04 检查 |
| K-04 | Windows | `codex_installer_test.dart` 的安装 / 升级用例用 sh 脚本模拟 codex，Windows 上跳过 | 已修复：Windows 上用 `.cmd` 脚本模拟，压缩用 System32 的 tar，不再跳过（需在 Windows 上实际运行确认） |
| K-05 | Windows arm64 | `native/*/scripts/build.ps1` 只编译 x64 | 已修复：两个脚本都加了 `-Arch x86_64\|arm64` 参数，默认按 VS 命令行的目标架构，不一致时报错；arm64 的 OpenSSL 用 `VC-WIN64-ARM`（需在 Windows arm64 上实际构建确认） |
| K-06 | Linux | 打开目录、打开链接依赖 `xdg-open`，有些精简发行版没有安装 | 不处理：目标环境（桌面发行版）默认带 `xdg-utils`；M-10 中验证 |
| K-07 | Windows | 无 BOM 的中文 PowerShell 构建脚本解析失败；MSVC 对 UTF-8 源码报告 C4819 / C2220 | 已修复：PowerShell 使用 UTF-8 BOM，CMake 显式启用 `/utf-8`，P-06 检查 |
| K-08 | Windows | 日志测试未 close，删除临时目录时报文件占用；重新初始化会复用旧日志文件 | 已修复：增加 `AppLog.close()`，初始化先关闭旧文件；P-07 检查 |
| K-09 | Windows | 同步测试无法直接启动 `dart.bat`，清理时访问未初始化变量 | 已修复：公共测试工具定位真正的 Dart 可执行文件，安全清理进程；P-07 与同步端到端测试检查 |
| K-10 | Windows | 拖放测试误用逻辑坐标；VNC 测试假设 TCP 分包合并及固定等待时间，跨平台或并行负载下误报 | 已修复：按平台模拟物理坐标；VNC 批量发送数据、直接发送首帧字节缓冲、等待实际首帧与覆盖结果；相关测试在三个平台通用 |
| K-11 | Windows | PowerShell 不检查原生命令退出码，编译失败可能继续安装或复制旧产物 | 已修复：两个库统一通过 `native/utils/windows_build.ps1` 检查退出码；OpenSSL 显式使用 `--libdir=lib` 与其他平台一致；P-06 检查 |
| K-12 | Windows | 英文界面在 960×640 最小窗口中，RDP 工具栏向右溢出 27 像素 | 已修复：窄工具栏使用图标按钮，保留中英文本地化提示；`layout_overflow_test.dart` 覆盖两种语言和三种窗口尺寸 |
| K-13 | Windows | FreeRDP 缺少 zlib 依赖；同时有 MinGW 时 CMake 会选中 GCC 或不兼容的 ccache，缺少 MSVC 对象文件而链接失败 | 已修复：构建静态 zlib，显式指定 MSVC 编译器并关闭自动 ccache，在胶水库链接 zlib；P-06 检查 |
| K-14 | Windows | RDP 胶水库的旧 Winsock / Shell 宏冲突、剪贴板进度标志旧别名不可用，静态库被当作 DLL 导入，通道库路径与系统库缺失 | 已修复：使用精简 Windows 头和正确包含顺序；三平台统一 `FD_PROGRESSUI`；静态导入声明、Windows 通道库根目录及 `credui` 链接；P-06 检查 |
| K-15 | Linux | RDP 测试服务端链接项目 OpenSSL 库却读取系统 pkg-config 元数据，带入不存在的 libjitterentropy.a，构建失败 | 已修复：与应用构建相同的 `CMAKE_PREFIX_PATH`，避免混用库与元数据；关闭测试服务端不需要的 systemd，保持剪贴板测试服务端链接完整；P-06 检查 |
| K-16 | Linux | 测试字体仅查找 truetype/noto，Ubuntu 将 Noto CJK 安装在 opentype/noto；品牌文字在宽字体下溢出 | 已修复：补充 Linux 字体位置，品牌文字在剩余宽度内按需缩小；现有终端与中英文布局测试回归 |
| K-17 | Linux | 原打包只有 x64 tar.gz，没有系统安装包，也未检查原生库缺失导致的功能降级 | 已修复：默认生成 deb 和便携包、架构对应输出、检查必需资源，从 ELF 自动计算 Depends；P-09 检查 |
| K-18 | Linux | 便携目录包含 `%` 时，GIO 在展开 `%%` 前检查 Exec 可执行文件，菜单入口无法加载 | 已修复：通过 `/usr/bin/env` 启动正确转义的绝对路径；P-09 使用真正的 GIO 启动并验证进程输出 |
| K-19 | Linux | 构建机安装 JDK 时，Android 间接依赖的可选 JNI 插件会生成 libdartjni.so，并依赖构建机的绝对 Java 路径 | 已修复：Linux CMake 关闭可选 JNI 查找；Linux 功能不使用 Java，分发包无需 JDK / JRE；P-09 检查 |

## 6. 验证记录

每完成一轮验证都更新这张表（写明日期、系统版本与架构、提交号），失败项在[已发现的平台问题](#5-已发现的平台问题)中登记。

| 项目 | macOS | Windows | Linux |
| --- | --- | --- | --- |
| 环境 | macOS 26.7 x86_64 | 2026-10-21，Windows 11 25H2（10.0.26200.9711）x64，Flutter 3.47.7 / Dart 3.13.5；基于 `3e59087` 工作区修复 | 2026-10-21，Ubuntu 26.04 LTS / Linux 7.0.0-38-generic x86_64，Flutter 3.47.7 / Dart 3.13.5；基于 `a318f6b` 工作区修复 |
| P-01 ~ P-06（`make test-platform`） | ✅ 2026-10-21 | 未验证 | ✅ 已纳入本轮最新平台 / 端到端验证，见后续记录 |
| 修复 K-01 ~ K-05 后的相关测试（test/platform、codex_installer、ssh / rdp / rdp_clipboard 端到端） | ✅ 2026-10-21，端到端测试实际执行未跳过 | 未验证 | ✅ 已纳入本轮最新平台 / 端到端验证，见后续记录 |
| `flutter test`（全部）与端到端测试 | 之前的开发过程中运行过，本轮未重新运行 | ✅ 2026-10-21，123 项通过 / 18 项跳过；同步端到端、Codex 安装器、VNC 本地模拟服务器实际执行 | ✅ 2026-10-21，139 项通过 / 6 项跳过；SSH / SFTP、RDP / 剪贴板、VNC 模拟服务器、同步端到端、Codex 安装器、原生加密实际执行；4 项仅 macOS，2 项 dsh 另行启用 |
| P-01 ~ P-07（扩展后的 `make test-platform`） | 本轮新增检查待实机重跑 | ✅ 2026-10-21，23 项通过 | ✅ 已纳入本轮最新平台 / 端到端验证，见后续记录 |
| P-01 ~ P-08（安装器扩展后的 `make test-platform`） | 新增检查待实机重跑 | ✅ 2026-10-21，26 项通过；新增测试静态检查无问题 | ✅ 已纳入本轮最新平台 / 端到端验证，见后续记录 |
| 无 Make 启动入口扩展验证 | 不适用新增脚本，平台测试待重跑 | ✅ 2026-10-21，平台测试 28 项通过；PATH 中无 Make 时 `windows/run.ps1 -PrepareOnly` 通过（已有原生库）；图形启动和全新原生编译待按 M-15 验证 | Windows 专用脚本不适用；✅ 2026-10-21，新 Bash 终端执行 make run，Debug 编译、图形启动、VM Service 和 q 正常退出通过 |
| P-01 ~ P-09（Linux 安装包扩展） | 新增检查待实机重跑 | 新增检查待实机重跑 | ✅ 2026-10-21，最终 28 项通过，含桌面 GIO 启动、JNI 约束和打包失败保护 |
| 静态检查 | 本轮未重跑 | ✅ 客户端 lib / test / hook 与 server 均无问题 | ✅ 客户端与服务端静态检查无问题 |
| dsh 真实安装端到端（`RMK_DSH_E2E=1`） | 本轮未重跑 | ✅ 2 项通过，下载 Node.js、npm 安装 dsh、ACP 启动与终端 JSON 协议联调实际执行 | ✅ 2 项通过，Node.js 24.22.0 / dsh 0.2.1-rc.2，npm 安装、ACP 和终端 JSON 协议实际执行；首次查询 TLS 中断，重试通过 |
| 同步服务端测试 / 编译 | 本轮未重跑 | ✅ `dart test` 2 项通过，`make server` 生成 `dist/remlark-sync-server/bundle/bin/server.exe` | ✅ `dart test` 2 项通过；`dart build cli` 生成 `dist/remlark-sync-server/bundle/bin/server` |
| 原生库编译与加载 | 本轮未重跑 | ✅ `make native-lib`；生成 RDP / SSH 加密 DLL；`native_crypto_test.dart` 实际执行未跳过，RDP FFI 加载、创建并释放会话通过；与 P 测试合计 25 项通过 | ✅ `make native-lib`、`make rdp-test-server`；RDP / SSH `.so` 和测试服务端编译通过，AES-GCM 对照和 RDP 端到端实际执行，`ldd -r` 无缺失库 / 未解析符号 |
| Windows Release 打包 | — | ✅ 默认 `make`，`dist/remlark-windows-x64.zip`；已核对 exe、RDP / crypto / sqlite DLL 与 AOT 资源齐全；RDP DLL 仅依赖系统库。未在干净机器上启动 | — |
| Windows 安装程序 | — | ✅ 默认 `make` 生成 `dist/remlark-1.0.0-windows-x64-setup.exe`；Inno Setup 6.7.3 编译通过，71 个条目完整性检查通过，含中英文、三项 VC++ 运行库与翻译许可证；M-14 实际安装 / 升级 / 卸载尚未执行 | — |
| 打包后的服务端 HTTP 冒烟测试 | 本轮未重跑 | 未执行：自动审批拒绝后台启动编译产物的操作，未返回具体原因；源码方式的双客户端同步端到端测试已执行 | ✅ AOT 产物启动成功；未授权 401、授权 PUT 200、索引读取与 SQLite 写入通过 |
| Linux Release 与安装包 | — | — | ✅ 默认 `make`；deb + tar.gz，109 个便携归档条目；所有必需原生库 / 资源齐全，无 JNI / Java 依赖；APT 模拟安装通过；包内 RDP 创建 / 释放与 AES-GCM NIST 对照 / 认证失败检查通过 |
| Linux 分发包图形冒烟 | — | — | ✅ deb 解包启动两次、便携包解压到中文 / 空格 / % 路径启动两次；X11 窗口显示、最小尺寸、数据目录 / 密钥持久化通过；截图与日志在 build/validation；未在干净系统安装 |
| M-01 ~ M-13 | 开发过程中使用过，没有按本清单逐项记录；arm64 未实机运行 | 未逐项手工验证；M-02 有中英文三种尺寸布局测试，M-09 真实安装和 M-13 自动同步覆盖部分流程；真实 SSH / RDP / VNC、DPI、干净机器启动等仍待验证 | 部分覆盖：deb 解包与便携包在本机桌面成功启动 / 重启、数据库 / master.key / 日志生成，密钥 600 且重启保留；最小尺寸 960×640；中英文三尺寸布局、真实本地 SSH / SFTP、RDP 测试服务端、dsh 与同步已自动覆盖。真实远程 Windows / macOS、系统对话框与拖放、干净机器安装 / 升级 / 卸载未逐项验证 |

本轮构建在 VS 2022 x64 Developer PowerShell 中执行，Perl / NASM 使用本机便携工具，仅在构建进程中补充 PATH；OpenSSL 首次构建使用 JOM 并行完成，随后 `make native-lib` 与默认 `make` 增量构建通过。依赖和本地冒烟脚本保留在忽略的 `build/` 中。

Linux 本轮原始日志与构建产物检查保留在忽略的 `build/validation/`；Flutter 安装在 `~/.local/opt/flutter`。系统依赖和后续复现命令见 [build-environment.md](build-environment.md#linuxubuntu--debian)。

2026-10-21 Linux 开发启动补验：初次直接 `make run` 因 Flutter 未在终端 PATH 中以 Error 127 失败；将 `~/.local/opt/flutter/bin` 持久配置到本机 `~/.bashrc` / `~/.profile` 后，从交互 Bash 实际运行 `make run`，Debug 构建与启动成功。已有终端先执行 build 文档中的 PATH export，新终端自动生效。

Windows ARM64 CI 发现系统 tar 创建中文路径时崩溃、ZIP 中文条目不可读，P-03 使用 Python 生成标准 PAX 夹具并检验真实解压；Windows 改用 Dart 流式解压，两种格式的 Windows 解码实现也在 macOS / Linux 上验证。

### 2026-10-21 GitHub Actions Release 验证

[Desktop Release #8](https://github.com/Remlark/Remlark/actions/runs/39593809838) 五路构建及发布任务全部成功，总耗时 20 分 38 秒；[v1.0.0](https://github.com/Remlark/Remlark/releases/tag/v1.0.0) 已发布。

| runner / CPU | 平台测试 | 构建结果 |
| --- | --- | --- |
| macos-15 / arm64 | 33 项通过 | Intel / Apple Silicon 通用 zip 与 DMG |
| windows-2022 / x64 | 38 项通过 | setup.exe 与便携 zip，附带 x64 CRT |
| windows-11-arm / arm64 | 38 项通过 | VS 2026 原生 ARM64 应用、setup.exe 与便携 zip，附带 ARM64 CRT |
| ubuntu-24.04 / x64 | 33 项通过 | amd64 deb 与 x64 tar.gz |
| ubuntu-24.04-arm / arm64 | 33 项通过 | arm64 deb 与 tar.gz |

发布任务验证 10 个附件完整后生成 SHA256SUMS，先上传草稿再公开。浏览器已确认 Actions Success、Release 为 Latest，附件齐全。本机补验：33 项平台测试、2 项 Codex 安装器测试通过；通用 DMG 完整性、macOS 主程序 / FFI 双架构、Linux 两种 ELF 架构、Windows 分发 PE 架构和发布校验和核对见本轮验证。M-16 的干净机器交互安装 / 升级 / 卸载仍需按清单执行。
