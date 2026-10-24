# 多平台测试

Remlark 是 Flutter 桌面应用，支持 macOS、Windows、Linux 三个平台。Flutter 桌面不能交叉编译，各平台的构建和测试都要在对应系统上执行。macOS（x86_64）、Windows x64 和 Linux x64 已有自动化验证记录；真实远程主机、干净机器安装等项目仍需按本文逐项验证。

本文列出：

1. 哪些功能和平台有关、各平台用的是什么实现；
2. 用来检查这些功能的单元测试（编号 P-xx）；
3. 依赖本机环境的端到端测试，以及各平台的准备步骤；
4. 自动化测试覆盖不到、需要手工验证的项目（编号 M-xx）；
5. 已经发现的平台问题。

2026-10-25 服务端 CI 更新（Step 107）：本机 macOS `make test-platform` 95 项通过、3 项条件跳过；服务端 35 项测试、静态检查及 macOS x64 实际编译/归档/解包启动/SQLite 往返通过。P-23 在本机覆盖六种目标的文件头、打包和故障夹具，不能替代其他系统实测；新增六路服务端 CI 尚未触发，Windows / Linux / macOS arm64 和 M-13 仍待验证。桌面矩阵继续在三个系统执行 `make test-platform`。

2026-10-25 Actions 存储更新（Step 108）：macOS 平台测试 97 项通过、3 项条件跳过，P-24 的分页/范围/API 失败保护及工作流配置测试通过。实际清理旧 release.yml 的 10 个 artifacts，共 485,762,798 字节，远端复核剩余 0 个；未改动 Release 或缓存。新版自动清理任务尚未在 CI 触发，Windows / Linux 测试及 M-27 待对应环境验证。

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
| 原生依赖源码下载 | `tools/utils/source_archive.py`、`native/rdp/scripts/` | 校验/退避重试、复用有效包，在临时目录调用系统 tar 后原子发布 | 同一下载/原子发布接口，使用 System32 tar；zlib 双来源及 SHA-256；非 UTF-8 日志兼容 | 与 macOS 共用 POSIX 入口 | P-26 | M-29 |
| 原生构建阶段与失败恢复 | `tools/utils/native_build_state.py`、`native/utils/`、原生脚本与 Release CI | 提前检查 Xcode/工具；universal 必须两架构阶段均完整 | 提前检查 cl 实际目标、MSYS2 和英文资源；状态绑定 MSVC | 提前检查开发包；arm64 统一 aarch64 目录 | P-27 | M-30 |
| RDP H.264 硬件解码 | [native/rdp/src/hwdec/](../native/rdp/src/hwdec/)、[rmk_h264.c](../native/rdp/src/rmk_h264.c)、`native/rdp/scripts/` 中的 FFmpeg 编译 | VideoToolbox；FFmpeg 由 `build.sh` 编译 | D3D11VA（FreeRDP 默认 DXVA2，改为显式指定）；FFmpeg 用 MSVC 编译，configure 经 MSYS2 bash 运行（`build_ffmpeg_msvc.sh`），ARM64 关闭汇编；需要 VS 英文语言包，脚本预设工具 PATH、保护 CL 编译选项并固定英文输出 | VAAPI，自动选择第一个可读写的 `/dev/dri/renderD*`；运行时依赖 libva2 / libva-drm2 | P-11 | M-17 |
| 打包 | [Makefile](../Makefile)、[Windows 安装器](../windows/packaging/) | `make mac` → zip | `make windows` → Inno Setup 安装 exe + 便携 zip，附带应用本地 VC++ 运行库 | `make linux` → deb + tar.gz，按 x64 / arm64 输出；发布前检查原生库和资源 | P-06、P-08、P-09 | M-12、M-14 |
| 可选 JNI 依赖 | `linux/CMakeLists.txt`，Flutter 间接依赖 | 无 Linux JNI 插件 | 可选插件，未发现 JDK 时不构建 | 关闭 Android 间接依赖引入的可选 JNI，避免携带构建机 Java 绝对路径 | P-09 | M-12 |
| 开发启动 | [Makefile](../Makefile)、[Windows 启动脚本](../windows/run.ps1) | `make run` | `windows/run.ps1` 无须 Make，按需构建原生库；也支持 `make run` | `make run` | P-08 | M-15 |
| 应用图标 | `tools/branding/`、`macos/Runner/Branding/`、`linux/packaging/` | Asset Catalog / AppIcon.icns；启动后刷新 NSApplication 图标 | exe 内嵌 7 帧 ICO，经窗口类 LoadIcon 关联 | PNG + .desktop，与 APPLICATION_ID 关联 | —（P-14 已按用户要求移除） | M-12、M-19 |
| 同步服务端 | [server/](../server/)、[server_bundle.py](../tools/release/server_bundle.py)、Release CI | x64 / arm64 独立 runner，分别发布 tar.gz | x64 / arm64 独立 runner，分别发布 zip（含 SQLite DLL） | x64 / arm64 独立 runner，分别发布 tar.gz | P-23、P-10；`server/` 中的 `dart test`；六路 CI 解包后真实读写 SQLite | M-13 |
| 真实 RDP 配置联调 | [rdp_live_test.dart](../test/platform/rdp_live_test.dart) | 显式传入应用数据目录，使用同一 RdpClient 与原生库；待实机执行 | 同左；Windows x64 已实际连接，数据目录通常为 `%APPDATA%\com.remlark\remlark` | 同 macOS，待实机执行 | P-12（显式启用） | M-05、M-17 |
| 源码编码与构建失败检查 | `windows/CMakeLists.txt`、`native/*/CMakeLists.txt`、`native/utils/windows_build.ps1` | UTF-8，shell 严格错误检查 | MSVC `/utf-8`；PowerShell 带 UTF-8 BOM，外部命令失败立即停止 | UTF-8，shell 严格错误检查 | P-06 | M-12 |
| 测试 Dart 子进程与日志关闭 | `test/helpers/platform_tools.dart`、`lib/utils/app_log.dart` | Dart 可执行文件；关闭日志释放句柄 | 定位 SDK 的 `dart.exe`；删除日志目录前关闭句柄 | 同 macOS | P-07 | M-01、M-13 |
| 编译与发布版本 | `VERSION`、`tools/utils/app_version.py`、`lib/utils/app_version.dart`、各平台打包入口 | Flutter build 数字版本 / 构建号写入 Info.plist；DMG 打包校验系统元数据 | Flutter build 写入 exe 四段资源，安装器校验并复用；独立 run 复用 Python 工具 | deb control 从 VERSION 读取，预发布映射为 ~ | P-13、P-10 | M-18 |
| Release CI | `.github/workflows/release.yml`、`tools/release/` | Intel / Apple Silicon 通用 zip + DMG，lipo 校验 | x64 / arm64 安装 exe + zip；匹配 CRT 与 Inno 架构 | 原生 x64 / arm64 runner，deb + tar.gz | P-10、P-08、P-09、P-11（原生库编译后重新执行 make test-platform，实际解码）；手工 build_only 验证分支且不发布，构建后 RMK_REQUIRE_RDP_NATIVE=1 禁止跳过解码 | M-16 |
| GitHub 软件更新 | `lib/modules/updates/`、`utils/git_credentials/`、`utils/script_utils.dart` | 通用 zip，签名/版本校验，App 交换、按需系统授权；共用 shell 助手为 UTF-8 无 BOM | x64/arm64 Inno 静默安装到原目录，备份与失败恢复、按需 UAC；两个 PowerShell 助手为 UTF-8 带 BOM | dpkg 管理的 deb 或便携 bundle 交换，按需 polkit；共用 shell 助手为 UTF-8 无 BOM | P-18/P-19；Git credential fill、助手握手、等待退出、非提权重启、脚本编码 | M-23 |
| macOS 发布自签 | `tools/release/macos_signing.py`、Release CI | 两个 Secrets 导入临时钥匙串，重签嵌套代码 / App / DMG，重建 zip；始终清理凭据并还原钥匙串搜索列表 | 不调用 Apple 工具，保持原有打包 | 不调用 Apple 工具，保持原有打包 | P-15 | M-20 |
| 共享代理配置与重连 | `modules/proxies/`、`host_repository.dart`、`ssh_connector.dart`、`rdp_session.dart` | 共用 drift/加密存储；SSH 与内嵌 RDP 在新连接/重连时解析共享配置 | 同左，不新增系统代理或注册表设置 | 同左，不修改系统代理环境变量 | P-16 | M-21 |
| SSH TCP 首次连接恢复 | `utils/network/`、`modules/ssh/proxy_socket.dart` | 独立策略识别 51/65 | 独立策略识别 10051/10065 | 独立策略识别 101/113 | P-20：有限重试、预算和非瞬态错误 | M-24 |
| 代理连通性检测 | `modules/proxies/proxy_connection_test.dart`、`modules/ssh/proxy_socket.dart`、`utils/network_endpoint.dart` | ProxyConnectionTest 接口，Dart Socket 的 HTTP CONNECT/SOCKS5 握手、认证、超时和取消；IPv6 目标 | 同左，不访问注册表或系统代理 | 同左，不调用系统网络命令 | P-17 | M-22 |
| RDP 显示控制协商 | `native/rdp/src/remlark_rdp.c` | 共用 FreeRDP 能力回调，协商后发送布局 | 同 macOS | 同 macOS | P-21 | M-25 |
| 运行中构建覆盖保护 | `tools/utils/build_guard/`、`tools/utils/app_version.py`、`Makefile`、`windows/run.ps1` | ps 子进程固定 UTF-8 locale，读取未转义的中文完整路径 | CIM 显式输出 UTF-8 JSON，按 Windows 路径规则比较 | procfs 读取 exe，识别 deleted 文件，comm 显式按 UTF-8 读取 | P-22 | M-26 |
| 构建保护真实进程测试夹具 | `tools/testing/build_guard_test.py`、`test/platform/fixtures/build_guard_probe.c` | xcrun clang 从源码编译本机架构的普通进程，避免复制系统二进制的 SIGKILL；等待就绪标记，验证默认/C locale | 复制 Python 为隔离应用，设置 PYTHONHOME / PATH；仓库文本显式 UTF-8；等待就绪标记，验证默认/C locale | 复制 Python 为隔离应用，设置 PYTHONHOME，兼容多入口 coreutils；等待就绪标记，验证默认/C locale | P-22 | — |
| 发布前平台专项测试工作流 | `.github/workflows/test.yml` | Intel / ARM64 独立 runner；ARM64 复用精确匹配的 universal 原生缓存；Xcode 测试夹具 | x64 / ARM64 独立 runner；PowerShell、Make、MSVC 测试夹具 | x64 / ARM64 独立 runner；安装运行库及桌面入口测试依赖 | P-25 | M-28 |
| Actions 临时产物清理 | `release.yml`、`tools/release/cleanup_artifacts.py` | 仅构建不上传，正式发布中转保留 7 天，publish 成功后只清理当前运行；失败保留供重跑 | 同左 | 同左；清理在独立 Ubuntu 任务运行 | P-24 | M-27 |
| CI 网络安装重试 | `release.yml`、`test.yml`、[retry_command.py](../tools/utils/retry_command.py) | git clone Flutter、brew、flutter 初始化在 bash 中经 python3 重试 | choco、MSYS2 pacman、flutter 初始化在 pwsh 中经 python3 重试，失败仍由 `$LASTEXITCODE` 判断；`.bat`/`.cmd` 按 PATH 解析 | apt-get、flutter 初始化重试；publish 的 gh release upload/edit 同样重试 | P-28 | M-31 |

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
| P-10 | [release_workflow_test.dart](../test/platform/release_workflow_test.dart) | 手工默认仅构建、正式标签仍发布，三个平台构建后强制加载原生库并重跑平台测试；配置读取兼容 CRLF / LF；拒绝错误版本标签、缺失附件时阻止发布、完整双架构矩阵生成正确 SHA-256 清单 | 自动发布与仅构建验证 |
| P-11 | [rdp_h264_test.dart](../test/platform/rdp_h264_test.dart) | 三个平台都有硬件解码实现且设备类型正确，CMake 按平台选择；FFmpeg 只编译 H.264 解码器并按平台开启硬件加速，Windows 用 MSVC /MT 编译；FreeRDP 开启 FFmpeg 硬件解码；连接参数不再强制关闭 H.264，设置中的硬件解码开关传到原生库；原生库内置探测帧与测试资源一致；已编译原生库时：编入解码器、设备类型与当前平台一致，macOS 上 VideoToolbox 必须可用（Windows / Linux 取决于显卡，CI 无显卡时为软件解码），并用与连接相同的 FreeRDP AVC420 流程实际解码 [h264_320x240.h264](../test/platform/fixtures/h264_320x240.h264)：软件解码、硬件解码（不可用时为软件解码）的左右两半颜色都正确；平坦区域逐像素 RGB 差不超过 4，双色交界两侧各 2 像素的色度插值差不超过 64，输出差异列供核对，无效数据返回失败不崩溃 | RDP H.264 硬件解码 |
| P-12 | [rdp_live_test.dart](../test/platform/rdp_live_test.dart) | 显式指定已授权的已保存 RDP 配置，默认跳过；通过 ORM 索引只读配置；测试硬解开关两种模式的真实认证、首帧、键盘触发更新，保存实际解码 PNG；通过 GDI TRACE 日志另行确认实际编码，不能用连接成功代替 H.264 / GPU 验证 | 真实 RDP、M-05 / M-17 部分验证 |

| P-13 | [app_version_test.dart](../test/platform/app_version_test.dart) | VERSION 是唯一来源，兼容 CRLF / 中文空格路径，拒绝无效 / 缺失 / 越界版本；构建号默认 1；预发布与 Windows 四段资源 / Debian ~ 映射；发布标签去掉构建号；实际子进程验证三平台编译参数与开发 run 参数、退出码；拒绝命令行覆盖和给旧 macOS 应用换名打包 | 编译与发布版本 |
| P-14（已移除） | — | Step 118 按用户要求删除图标自动化测试及 Swift 夹具，编号保留不复用；历史测试记录仅供追溯 | 图标改用 M-12、M-19 手工检查 |
| P-15 | [macos_signing_test.dart](../test/platform/macos_signing_test.dart)、`fixtures/macos_signing_checks.py` | 三平台检查仅两项凭据、自动识别唯一身份 / 拒绝缺失或多身份、自动生成钥匙串密码、缺失 / 损坏凭据、失败日志不泄密、嵌套签名顺序及部分失败清理；Windows / Linux 拒绝 Apple 工具；macOS 创建一次性证书，真实导入 / 重签 App / 严格验证 / 还原搜索列表并移除私钥 | macOS 发布自签 |
| P-16 | [proxy_profiles_test.dart](../test/platform/proxy_profiles_test.dart) | 真实 ORM 存储共享代理，SSH/RDP/VNC 内置 SSH 共用引用；变更后重连解析新参数、连接快照及目标端口保持、引用计数和删除保护；三平台执行相同实现 | 共享代理配置与重连 |
| P-17 | [proxy_connection_test.dart](../test/platform/proxy_connection_test.dart) | 三平台真实本地 Socket 夹具；HTTP 认证/407、SOCKS5 认证/非法响应、总超时与慢速响应、取消断开、禁止无代理直连、目标格式与 IPv6 authority/地址类型 | 可选代理连通性检测 |
| P-18 | [update_platform_test.dart](../test/platform/update_platform_test.dart) | 六种平台/架构附件映射、Linux deb/便携分流、不支持架构拒绝、current() 选择 | GitHub 升级、M-23 |
| P-21 | [rdp_display_control_test.dart](../test/platform/rdp_display_control_test.dart) | 编译并运行生产 C 函数：能力到达前不发送、尺寸合并、重复轮询、旧通道隔离、重新协商；检查回调注册和断开重置。macOS/Linux 使用 cc，Windows 使用开发者终端 cl；无编译器时动态用例跳过，RMK_REQUIRE_RDP_NATIVE=1 时禁止跳过 | RDP 显示控制、M-25 |
| P-20 | [connect_retry_test.dart](../test/platform/connect_retry_test.dart) | 三平台错误码分别验证；首次不可达后恢复、持续失败最多四次、总预算不重置；连接拒绝/权限/非 Socket 错误不重试；当前平台策略选择 | SSH TCP 首次连接恢复、M-24 |
| P-19 | [update_installation_test.dart](../test/platform/update_installation_test.dart) | 实际隔离 Git helper；POSIX 未提交不安装、等待退出、失败回滚、特殊路径；macOS 真实签名/版本校验及 App 替换；Linux 便携解压与交换；任意宿主检查 Windows x64/arm64 BOM 和 POSIX shebang；Windows 实际解析 PowerShell 助手、执行假安装器并核对成功/失败恢复及结果文件 | 点击升级后安装、M-23 |
| P-22 | [build_guard_test.dart](../test/platform/build_guard_test.dart) | 调用 12 项 Python 检查：三个桌面目标、路径边界/中文空格/大小写、独立副本放行、自定义输出和符号链接、三平台进程解析、查询环境透传及失败保护、默认/C locale 的真实进程存活时拒绝/退出后放行；包装入口失败时不启动 Flutter；仓库文本显式按 UTF-8 读取 | 构建覆盖保护、M-26 |
| P-23 | [server_bundle_test.dart](../test/platform/server_bundle_test.dart)、[server_bundle_test.py](../tools/testing/server_bundle_test.py) | 六路服务端矩阵、发布依赖、macOS 双架构独立 runner；六种原生文件头与错误平台/架构、缺少/空主程序和 SQLite 库拒绝打包；压缩包布局与 POSIX 执行权限、额外资源保留；P-10 检查缺少服务端附件时禁止发布 | 同步服务端独立发布、M-13 |
| P-24 | [artifact_cleanup_test.dart](../test/platform/artifact_cleanup_test.dart)、[artifact_cleanup_test.py](../tools/testing/artifact_cleanup_test.py) | 三平台执行相同清理逻辑；仅构建不上传、正式中转保留 7 天且重跑覆盖、仅 publish 成功后清理（不使用 always()）；只查询当前运行的 artifacts 并分页先快照再删除，不访问仓库级列表，保护非托管文件及 API 失败上报 | Actions 存储、M-27 |
| P-28 | [ci_retry_test.dart](../test/platform/ci_retry_test.dart)、[retry_command_test.py](../tools/testing/retry_command_test.py) | 6 项 Python 检查：指数退避、重试前清理半成品且首次不清理、最后退出码传递、命令不存在不重试、非法参数、真实子进程下 `--` 可省略且保留目标命令的 --选项/含空格参数；两个工作流所有网络安装都经过重试工具且无裸命令 | CI 网络安装、M-31 |
| P-25 | [platform_test_workflow_test.dart](../test/platform/platform_test_workflow_test.dart) | 独立 test* 触发及手动入口、三平台双架构六路矩阵、锁文件与每路仅一次平台专项、禁止客户端全量/dsh/服务端测试及服务端依赖；精确原生缓存及缺失摘要；禁止应用/原生产品构建、上传产物、签名凭据及发布 | 发布前测试、M-28 |
| P-26 | [source_archive_test.dart](../test/platform/source_archive_test.dart)、[source_archive_test.py](../tools/testing/source_archive_test.py) | 20 项 Python 检查：实际 gzip/tar/SHA、tar 仅接收 ASCII 相对参数（Windows bsdtar 中文路径）、错误响应/截断/CRC、退避/镜像/慢速预算、本地磁盘失败不重试、有效包复用、源码原子发布/回滚、缺失关键文件、非 UTF-8 日志与 CLI；三平台下载入口及 Windows zlib 下载先于编译 | 原生源码下载、M-29 |
| P-27 | [native_build_resilience_test.dart](../test/platform/native_build_resilience_test.dart)、`tools/testing/native_build_state_test.py`、`tools/testing/windows_build_checks.ps1` | 15 项 Python 检查：阶段完整性/摘要/旧配方/错架构/位置/工具链缓存身份、半安装不混旧产物、通用双架构及 CLI；实际 POSIX 缺工具/架构/语言前置失败；Windows 包装器、实际 Fetch 参数和无工具驱动拒绝；缓存恢复/保存路径集合一致及完整/阶段缓存区分 | 编译恢复、M-30 |

P-11 的测试帧由 libx264 生成（BT.709 全范围，与 FreeRDP 的 YUV 转换一致），同一份字节内置在 [rmk_h264_probe_frame.h](../native/rdp/src/rmk_h264_probe_frame.h) 中，原生库首次连接时用它实际硬件解码一帧，解码成功且颜色正确才启用硬件（虚拟机、驱动异常等能创建设备却无法解码的环境会改用软件解码）。重新生成时两处同步更新：

```bash
ffmpeg -f lavfi -i "color=c=0x3080C0:s=320x240:d=0.04,drawbox=x=0:y=0:w=160:h=240:color=0xE04020:t=fill,format=rgb24,scale=out_color_matrix=bt709:out_range=pc,format=yuvj420p" \
  -frames:v 1 -c:v libx264 -profile:v baseline -x264-params keyint=1 -bsf:v h264_mp4toannexb -f h264 test/platform/fixtures/h264_320x240.h264
```

Release CI 在原生库编译完成后再次运行 P-11，五个平台架构都实际执行解码测试（runner 无显卡时验证软件解码路径），失败时不发布。

P-06 同时检查 FreeRDP 禁用宿主仓库 Git 标签版本探测，以及 Windows 下载源码使用系统 tar，避免应用版本改变库名或 Git Bash tar 误解析盘符。

### P-12：显式启用的真实 RDP 主机联调

[rdp_live_test.dart](../test/platform/rdp_live_test.dart) 默认跳过，不访问用户数据或网络。用户授权测试某个已保存密码的 RDP 主机后，显式传入应用数据目录、唯一的主机名称与截图目录：通过现有 ORM 的 protocol 索引读取配置，数据库禁止写入与迁移，凭据只在内存中解密，不输出密码。依次测试硬解设置开启 / 关闭两种连接，验证认证、非空首帧、Windows 键切换开始菜单触发画面变化，并保存 BGRA 解码后的 PNG；等待登录画面稳定后再操作，结束发送 Escape 并断开连接。禁用剪贴板与目录共享。

Windows PowerShell 示例（变量中填写已授权的本机配置；不把凭据写入命令）：

```powershell
$env:RMK_RDP_LIVE_DATA_DIR = "$env:APPDATA/com.remlark/remlark"
$env:RMK_RDP_LIVE_HOST = '<已授权的 RDP 主机名称>'
$env:RMK_RDP_LIVE_OUTPUT = "$PWD/build/validation/rdp-live"
$env:WLOG_LEVEL = 'ERROR'
$env:WLOG_FILTER = 'com.freerdp.gdi:TRACE,com.freerdp.codec:DEBUG'
flutter test --no-pub test/platform/rdp_live_test.dart
```

三平台共用同一测试，通过显式目录参数定位配置；本轮仅在 Windows x64 执行。P-12 的通过只证明真实连接、帧与输入，不能替代 M-17：须从原生日志中的 `codec=RDPGFX_CODECID_AVC420/AVC444/AVC444v2` 确认服务器实际发送 H.264，再结合本机硬件探测与 GPU 负载验证硬解。仅出现 Progressive / ClearCodec 时不计为 H.264 解码成功。

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
- **Linux**（以 Ubuntu 为例）：`clang cmake ninja-build pkg-config libgtk-3-dev nasm libva-dev`、`openssh-server`、`xdg-utils`、`zip unzip`；编译 FreeRDP 需要的开发包见 `native/rdp/scripts/build.sh`。

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
| M-13 | 同步服务端 | 三平台的 x64 / arm64 分别下载匹配架构的服务端包，整体解压 `bundle/`，在无 Dart SDK 的干净机器用 `--port --token` 启动；两个客户端同步主机与密钥；验证 HTTPS 证书与重启后数据库持久化。macOS 两个附件分别在 Intel / Apple Silicon 上运行，不以 Rosetta 代替原生验证 |
| M-14 | Windows 安装、升级与卸载 | Windows 10 / 11 x64 干净环境运行 setup；中英文向导、安装目录、开始菜单与可选桌面入口正确；启动不要求手工安装 VC++；关闭运行中的应用后覆盖升级；卸载程序及快捷方式移除，数据库、凭据与日志保留；macOS / Linux 不适用 |
| M-15 | Windows 无 Make 开发启动 | 未安装 Make、已有 Flutter 与 VS C++ 的 Windows x64 环境执行 `powershell -NoProfile -ExecutionPolicy Bypass -File windows/run.ps1`，缺少原生库时按文档准备 Perl / NASM 后可编译并启动；已有原生库时不重复编译；`-RebuildNative` 强制重编译；`-PrepareOnly` 不打开应用；macOS / Linux 按 `make run` 验证 |
| M-18 | 编译版本 | 将 VERSION 改为新的测试版本后重新构建：macOS Finder 应用信息显示数字版本和构建号，Windows exe / 安装器属性显示相同四段资源版本，Linux deb 元数据显示正确版本；预发布 deb 低于对应正式版；正式发布标签等于 v + VERSION 的版本号（不含构建号）。开发 run 的系统元数据使用 Flutter 默认值，Dart / AI clientInfo 使用 VERSION；不把开发包用于分发 |
| M-19 | 应用图标 | macOS 从 Finder / make run 启动新版，Dock 显示“连接之门”；固定到 Dock 后退出 / 重开、替换旧版后重开图标正确；Windows 任务栏 / 桌面快捷方式、Linux 应用菜单 / 任务栏使用相同品牌图标。运行中刷新不等于清理系统为旧路径保留的静态固定项 |
| M-17 | RDP H.264 硬件解码 | 连接开启 H.264 的 Windows 服务器（组策略“远程桌面会话主机 → 远程会话环境”中开启“为远程桌面连接优先使用 H.264/AVC 444 图形模式”与“配置 H.264/AVC 硬件编码”），播放视频或拖动窗口：画面正常、无花屏与色偏；日志中连接行显示“H.264 硬件解码（videotoolbox / d3d11va / vaapi）”；活动监视器 / 任务管理器 / `intel_gpu_top` 或 `radeontop` 中可见 GPU 视频解码负载，CPU 占用低于软件解码时（在设置 → 远程桌面中关闭“RDP 硬件解码”后新建连接即为软件解码，日志显示“设置中已关闭硬件解码”，用于对比）；设置页说明显示本机可用的设备名，显卡不支持时开关禁用；Linux 无 VAAPI 驱动或 Windows 无显卡时日志显示软件解码且画面正常 |
| M-16 | Release 安装验证 | 在干净的 Windows / Linux x64、arm64 与 Intel / Apple Silicon macOS 下载附件，验证 SHA256SUMS，安装、启动、升级、卸载并连接 SSH / RDP；macOS DMG 拖入 Applications。macOS CI 使用固定自签证书，尚未公证；Windows 未签名，CI 成功不代替实机交互验证 |
| M-27 | Actions 存储 | 仅构建运行结束后没有 packages/logs artifacts，cleanup 跳过；正式发布成功后 Release 的 16 个附件及 SHA256SUMS 可下载，当前运行的中转包已删除。人为让一路构建失败：cleanup 跳过，其他平台包保留；Re-run failed jobs 后 publish 拿到完整矩阵并发布，随后清理当前运行。其他历史运行的包和原生缓存不受影响 |
| M-28 | 发布前平台专项测试 | 推送新的 test* 标签，确认仅 Platform Tests 触发，检出标签提交且六路各只执行一次 make test-platform，没有客户端全量/dsh/服务端测试及服务端依赖安装，不取消其他 runner；检查原生缓存命中及缺失摘要，缺失时不得编译原生库；无应用/服务端产品构建、签名、打包、artifact 或 Release。后续推送 v* 标签仍独立触发正式发布 |
| M-29 | 原生源码下载与构建 | 三平台分别执行 make test-platform；在对应系统使用无源码缓存的独立检出目录验证原生构建。Windows x64/arm64 均应在 OpenSSL 编译前完成 zlib/FFmpeg 下载校验；错误响应明确重试/回退且不解压损坏文件，通过校验后继续构建。实际 Windows tar/MSVC 集成及外网偶发响应需对应 runner 验证 |
| M-30 | 阶段完成与缓存恢复 | 三平台执行 make test-platform；在独立环境验证普通构建失败后，仅保存已完成阶段和有效源码包，重试应复用已完成 OpenSSL 等依赖，未完成阶段重建；胶水 C 改动不作废第三方阶段缓存；MSVC/工作区/校验器变化不误命中；macOS universal 缺任一架构或 SSH 库不得保存完整缓存；强制取消/runner 故障可能无法执行保存步骤 |
| M-31 | CI 网络安装重试 | 在三平台 runner 查看日志，apt-get/brew/choco/pacman/flutter/git clone 均出现 `==> run (attempt 1/3)`；Windows pwsh 下 choco、MSYS2 bash 及 flutter.bat 能正常启动且失败仍被 `$LASTEXITCODE` 拦截；网络偶发失败时出现重试并继续 |

M-20：下载新 CI 的 macOS zip / DMG，核对 `codesign -dv --verbose=4` 的 Authority 是固定自签名称、不是 `Signature=adhoc`，执行 `codesign --verify --deep --strict --all-architectures /Applications/remlark.app`。分别在 Intel / Apple Silicon 干净系统检查首次 Gatekeeper 放行，再覆盖安装同证书的新版本，记录是否再次放行及辅助功能等隐私权限是否保留；不以自签或单元测试保证系统免授权。检查 Actions 日志不含证书密码，缺失 Secret 应在构建前失败，失败构建不得上传可发布附件。

M-21：在 macOS / Windows / Linux 分别新增 HTTP 和 SOCKS5 代理（含认证），在 SSH 与 RDP 主机中选择并实际连接；两台主机引用同一代理后修改地址/凭据，确认已建立会话不被打断、新连接和重连使用新参数。VNC 内置 SSH 验证终端/文件传输代理，不把 RFB 画面当作代理隧道。使用中的代理不能删除；切换主机代理后才可删除。导入旧配置和跨设备同步后检查代理参数、认证、分组及主机同步状态；未保存主机时打开管理弹窗再取消，原选择不变。

M-22：三平台分别打开只有一条代理和较多代理的管理弹窗，检查紧凑布局、内部滚动、固定搜索/关闭及中英文最小窗口。添加/编辑代理时验证 HTTP、SOCKS5（含认证）连接指定目标；错误密码、无法访问的目标、无响应端口应显示失败或超时，但仍能保存有效配置。测试进行中修改参数应取消并清除旧结果，保存或关闭不等待测试结束；再次打开不显示旧结果。内网限制下改用允许访问的目标，测试目标不随代理持久化。检测通过只表示代理隧道建立，不替代 SSH/RDP 登录验证。

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
| K-20 | Windows | FFmpeg 构建在普通 VS PowerShell 中找不到 cygpath；MSYS2 将 CL 中的 /FS 转成路径；只安装中文 VS 资源时 configure 无法识别 MSVC | 已修复：先设置 MSYS2 工具 PATH，禁止转换 CL，固定 VSLANG=1033 并检查英文资源；缺少 en-US 语言包时明确提示安装；P-11 检查 |
| K-21 | Windows | FFmpeg MSVC 编译成功后直接安装 avcodec.lib / swscale.lib / avutil.lib，脚本却尝试重命名不存在的 libxxx.a，导致 make native-lib 失败 | 已修复：保留 MSVC 库名，检查三项静态库完整性；P-11 检查 |
| K-22 | Windows | FreeRDP 3.32.2 的 h264_ffmpeg.c 在硬解分支块末尾使用无语句标签，MSVC C11 报 C2143 | 已修复：build.ps1 对 fail_hwdevice_create 标签补空语句，补丁可重复执行；P-11 检查 |
| K-23 | Windows | P-06 的 NMake 环境变量测试未指定进程级执行策略，默认禁止脚本时无法加载 windows_build.ps1 | 已修复：与同文件其他执行脚本的测试一致，使用 PowerShell -ExecutionPolicy Bypass；不修改系统策略 |

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
| P-11 RDP H.264 硬件解码（Step 81） | ✅ 2026-10-21，macOS x86_64，基于 `f06a681` 工作区：`build.sh` x86_64 / arm64 编译通过；`make test-platform` 41 项通过，探测到 VideoToolbox（实际解码校验通过）；P-11 解码测试中软件 / VideoToolbox 解码颜色正确且一致；RDP 端到端与剪贴板测试通过；真实 Windows 服务器（M-17）待验证 | ✅ 2026-10-21，Windows 11 25H2 x64，基于 `4e3c143` 工作区：修复 K-20 ~ K-23 后 `make native-lib` 成功，`make test-platform` 46 项通过、无跳过；P-11 的 8 项包含实际帧解码、颜色与软解一致性、无效数据处理。本机只有 Remote Display / Basic Display Adapter，探测为 d3d11va 不可用，实际验证软件解码与硬件请求自动回退；真实 GPU 硬解、ARM64 与 M-17 未验证（用户暂无测试主机） | ✅ 2026-10-21，Ubuntu 26.04 x86_64，基于 `e2a7417` 工作区：`make native-lib` 成功；`make test-platform` 41 项通过 / P-12 默认跳过 1 项，P-11 的 8 项全部实际执行；软件解码与请求硬解时的软件回退颜色正确且逐像素一致，无效数据返回失败。本机为虚拟显示设备（1234:1111），无 `/dev/dri/renderD*`，VAAPI 不可用；真实 GPU 硬解、ARM64 与 M-17 待验证 |
| Windows H.264 设置与回归（Step 83.1） | 本轮未重跑 | ✅ 2026-10-21：硬件解码设置 3 项、中英文三种窗口尺寸布局 2 项、原生 AES-GCM 1 项，共 6 项通过；相关 Dart 静态检查无问题，FreeRDP 补丁重复执行不改动源码 | 本轮未重跑 |
| P-12 真实 RDP 联调 / M-17 部分验证（Step 83.2） | 未执行 | ✅ 2026-10-21，使用软件中保存的 AMD-Windows，硬解设置开启 / 关闭两次真实连接通过；均为 1280×800，分别收到 36 / 38 次更新，Windows 键打开开始菜单、Escape 关闭正常，截图人工检查未见明显花屏。最终 GDI TRACE 观察到 ClearCodec 128 条、Progressive 14 条、Uncompressed 4 条，未观察到 AVC420 / AVC444；本机仍为 d3d11va 不可用，因此不计为真实 H.264 或 GPU 硬解通过。`make test-platform` 46 项通过 / P-12 默认跳过 1 项；显式启用 P-12 的真实测试 1 项通过，静态检查无问题 | 未执行 |
| Linux H.264 全量回归（Step 83.3） | 本轮未重跑 | 本轮未重跑 | ✅ 2026-10-21，`make test` 客户端 156 项通过 / 7 项按条件跳过、服务端 2 项通过；包含 RDP 端到端 / 剪贴板、硬解设置 3 项及中英文三尺寸布局 2 项；`make analyze` 客户端与服务端无问题；修正两处既有花括号 lint 提示 |
| Linux H.264 Release（Step 83.3） | — | — | ✅ 默认 `make` 编译与打包通过，生成 deb / tar.gz；两包 RDP 库与本轮构建一致，包内库实际解码最大 RGB 差为 0，`ldd -r` 无缺失依赖；deb 声明 libva2 / libva-drm2，APT 模拟安装通过；deb 解包后 Xvfb 隔离启动两次、最小尺寸与密钥持久化通过，截图检查正常 |
| M-01 ~ M-13 | 开发过程中使用过，没有按本清单逐项记录；arm64 未实机运行 | 未逐项手工验证；M-02 有中英文三种尺寸布局测试，M-09 真实安装和 M-13 自动同步覆盖部分流程；真实 SSH / RDP / VNC、DPI、干净机器启动等仍待验证 | 部分覆盖：deb 解包与便携包在本机桌面成功启动 / 重启、数据库 / master.key / 日志生成，密钥 600 且重启保留；最小尺寸 960×640；中英文三尺寸布局、真实本地 SSH / SFTP、RDP 测试服务端、dsh 与同步已自动覆盖。真实远程 Windows / macOS、系统对话框与拖放、干净机器安装 / 升级 / 卸载未逐项验证 |

本轮构建在 VS 2022 x64 Developer PowerShell 中执行，Perl / NASM 使用本机便携工具，仅在构建进程中补充 PATH；OpenSSL 首次构建使用 JOM 并行完成，随后 `make native-lib` 与默认 `make` 增量构建通过。依赖和本地冒烟脚本保留在忽略的 `build/` 中。

Windows H.264 本轮日志保存在 `build/validation/windows-h264-native.log`、`windows-h264-platform.log`、`windows-h264-ui.log` 与 `windows-h264-analyze.log`。MSYS2、Python 3.13.5 与匹配 MSVC 14.44.35229 的微软英文资源放在忽略的 `build/tools/`，英文资源在本地编译器副本中使用，未修改系统 VS 安装；构建入口为 `build/validation/run-h264-native.ps1`，平台测试在当前进程 PATH 中优先使用本地 Python。

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

2026-10-21 Linux H.264 补验（基于 `e2a7417`）：原生构建、平台测试、全量测试、静态检查、Release 构建和包内解码日志分别保存在 `build/validation/linux-h264-{native,platform,test,analyze,release,packaged-decode}.log`；图形启动日志为 `linux-h264-gui.log`，截图为 `linux-h264-gui/linux-release.png`。首次图形冒烟脚本未将 GDK_BACKEND 传给 Python，导致截图工具选择 Wayland 而失败；显式设置 `GDK_BACKEND=x11` 后，deb 解包启动与截图检查通过。NASM / libva-dev 的用户态依赖与复现方式见构建环境文档；没有实际 GPU 渲染节点，不将软件回退测试记为 GPU 硬解通过。


### 2026-10-21 硬件加速版本 GitHub Actions 全矩阵验证（Step 84）

[Desktop Build #11](https://github.com/Remlark/Remlark/actions/runs/39615318096) 使用提交 `2aa69f3`，五路构建与构建后测试全部成功。手工运行保持 `build_only=true`、tag 留空，构建 master 分支；发布任务已跳过，未修改现有 v1.0.0 Release。

| runner / CPU | 构建后 make test-platform | H.264 实测 | 构建产物 |
| --- | --- | --- | --- |
| macos-15 / arm64 | 42 项通过 / 1 项跳过 | VideoToolbox；平坦区域最大 RGB 差 0，交界第 160 / 161 列差 49 | Intel / Apple Silicon 通用 zip + DMG，主程序与 FFI 双架构校验通过 |
| windows-2022 / x64 | 47 项通过 / 1 项跳过 | D3D11VA 不可用，软件解码与请求硬解时回退，RGB 差 0 | setup.exe + 便携 zip |
| windows-11-arm / arm64 | 47 项通过 / 1 项跳过 | D3D11VA 不可用，软件解码与请求硬解时回退，RGB 差 0 | ARM64 setup.exe + 便携 zip |
| ubuntu-24.04 / x64 | 42 项通过 / 1 项跳过 | VAAPI 不可用，软件解码与请求硬解时回退，RGB 差 0 | amd64 deb + x64 tar.gz |
| ubuntu-24.04-arm / arm64 | 42 项通过 / 1 项跳过 | VAAPI 不可用，软件解码与请求硬解时回退，RGB 差 0 | arm64 deb + tar.gz |

五路均实际执行 P-11，构建后设置 `RMK_REQUIRE_RDP_NATIVE=1`，原生库无法加载时立即失败；唯一跳过项为需显式提供真实主机的 P-12。全部五组安装包上传到 Actions artifacts，保留 7 天。Windows / Linux 的真实 GPU 硬解及真实远程服务器协商编码仍需 M-17，不能由无显卡 runner 的软件回退测试代替。

本轮修复：新增仅构建入口；修复新增 P-10 检查在 Windows CRLF 下的误报；P-11 原先要求整帧软硬解差不超过 4，macOS ARM64 在双色交界两列出现有限差异。现平坦区域仍逐像素要求不超过 4，只对交界两侧各 2 像素允许不超过 64，并输出差异列；云端证实平坦区域完全一致，没有把整帧颜色误差阈值放宽。

本机补验：`make test-platform` 42 项通过 / P-12 跳过，启用强制原生库检查的 P-11 通过；静态检查通过。第二轮 Linux 双架构便携包已下载核对，主程序、RDP 与 SSH 加密库的 ELF 架构分别为 x86-64 / AArch64。最终五路日志与任务状态保存在忽略目录 `build/validation/github-h264/final/`。


### 2026-10-21 VERSION 统一版本验证（Step 85）

[GitHub Actions](https://github.com/Remlark/Remlark/actions/runs/39622112845) 使用提交 `cb93ed1`、`VERSION=1.0.0+1`，五路全部成功；应用与同步服务 pubspec 均不再声明版本。发布任务按仅构建模式跳过，五组安装包已上传。

| runner / CPU | 构建前后 make test-platform | 编译与打包结果 |
| --- | --- | --- |
| macos-15 / arm64 | 各 48 项通过 / P-12 跳过 | 通用 app / zip / DMG；DMG 入口核对 Info.plist 版本 1.0.0、构建号 1 |
| windows-2022 / x64 | 各 54 项通过 / P-12 跳过 | exe / 安装器 / zip；打包入口核对 exe 数字资源版本 1.0.0.1 |
| windows-11-arm / arm64 | 各 54 项通过 / P-12 跳过 | ARM64 exe / 安装器 / zip；同样通过 1.0.0.1 资源版本核对 |
| ubuntu-24.04 / x64 | 各 48 项通过 / P-12 跳过 | amd64 deb / x64 tar.gz；Debian control 与文件名使用 VERSION |
| ubuntu-24.04-arm / arm64 | 各 48 项通过 / P-12 跳过 | arm64 deb / tar.gz；Debian control 与文件名使用 VERSION |

P-13 在三个系统实际执行，隔离夹具的 VERSION 为 `2.3.4-rc.2+17`，pubspec 故意为 `9.9.9+9`，验证没有读取 pubspec；真实替身子进程验证编译版本、构建号、Dart define、开发 run 参数与退出码。macOS 旧应用元数据不匹配时拒绝打包，Windows 专项也验证旧 exe 被拒绝。发布清单夹具继续验证版本标签与十项附件 SHA-256。

本机 `make test-platform` 48 项通过 / P-12 跳过，Codex 7 项、服务端 2 项通过，静态检查通过。实际 macOS Release 编译与 Info.plist 核对通过。日志与状态保存在忽略目录 `build/validation/version/`；M-18 的系统界面显示、安装升级等交互检查仍按手工清单验证。


### 2026-10-21 macOS Dock 图标刷新验证（Step 86）

Debug / Release 应用中的 AppIcon.icns 已为“连接之门”，旧图标现象不能归因于 PNG 未替换。新增启动完成时从当前应用包读取 AppIcon.icns 并设置 NSApplication.applicationIconImage，避免仅依赖系统历史图标；缺少资源时保留系统原图。Windows 继续使用 exe 内嵌 ICO，Linux 继续使用应用 ID / desktop 图标关联。

[GitHub Actions](https://github.com/Remlark/Remlark/actions/runs/39625870166) 使用提交 `5eacd93`，五路编译 / 打包全部成功，发布任务跳过。构建前后 `make test-platform`：macOS / Linux 双架构各 50 项通过、Windows 双架构各 56 项通过，均仅跳过需真实主机的 P-12。

P-14 在三个平台核对品牌 PNG、Windows ICO 最大帧的实际 RGBA 像素及系统图标入口。macOS 额外用 swiftc 编译实际 ApplicationIcon 实现，在禁止窗口和 Dock 项的隐藏测试进程中先设置其他图标，再刷新并读回 NSApplication 图标比较像素；缺失资源时保持原图标。macOS 15 将图标栅格化为 512 像素，macOS 26 使用 1024 像素，比较时使用包中相同密度的表示，只允许 8 位色彩转换的一档舍入差，避免跨密度缩放产生误报。

本机 macOS 专项及 50 项平台测试通过，静态检查无问题，Debug / Release 均重新编译；通用 zip / DMG 已重新生成，并刷新本地 .app 目录时间。验证图像与云端日志位于 `build/validation/dock-icon/`；其中 actual.png / expected.png 为隐藏测试进程的图标读回结果，不是用户 Dock 截图。真实 Dock 固定项的退出 / 重开和旧路径副本仍按 M-19 手工确认。


### Step 87：macOS 固定自签发布本机验证

本机 `make test-platform` 52 项通过 / P-12 跳过，新增 Dart 测试静态检查通过。P-15 的 Python 7 项检查全部通过，其中 macOS 使用临时生成的一次性代码签名证书，真实导入带私钥的 P12、重复签 App 并比较证书身份要求，校验 zip 解压后的 App 以及签名 DMG；结束时验证钥匙串删除及搜索列表还原。未修改系统证书信任设置，也未访问用户上传的 Secrets。

Windows / Linux 本轮尚未执行，Release CI 保留五路构建前后的 `make test-platform`。使用实际仓库 Secrets 的云端签名及 M-20 仍待推送后验证，不以一次性测试证书替代实际发布验证。


Step 88（两项 Secrets 简化）：本机 `make test-platform` 52 项通过 / P-12 跳过。P-15 的 9 项 Python 检查覆盖证书指纹自动识别、同身份去重、无身份与多身份拒绝、钥匙串密码自动生成，以及只提供证书 / 密码时的真实 App / zip / DMG 签名。Windows / Linux 的完整平台测试及仓库实际证书导入待新版 CI 执行。


### Step 90：共享代理配置

本机 macOS `make test-platform` 53 项通过，P-12 真实 RDP 因未提供已授权配置而跳过。新增 P-16 无平台分支，三平台共用同一仓库与解析逻辑；未修改原生代理接口。Windows/Linux 当前未执行新版 `make test-platform`，需由对应系统或现有 CI 验证；M-21 的真实远程代理链路仍待实机验证。本机临时 sshd 的 SSH、跳板、HTTP 和 SOCKS5 回归已通过，不以此替代真实 RDP 认证。


### Step 91：紧凑管理与连接测试

本机 macOS `make test-platform` 62 项通过，P-12 仍因缺少真实 RDP 配置跳过；新增 P-17 的 9 项使用本地回环 TCP 服务验证真实协议，不访问默认外网测试目标。既有临时 sshd 的 12 项回归通过，覆盖带认证的 SOCKS5、HTTP 和跳板。Windows/Linux 未在本机执行，需运行相同 make test-platform 和 M-22；共享 Socket 实现无 OS 分支，不代表真实三平台远端代理链路已全部验证。

### M-23：GitHub 点击升级后自动安装（macOS / Windows / Linux）

Step 109 补充：Windows 中英文系统分别使用 PowerShell 5.1 验证普通目录与需 UAC 目录的升级；检查下载后生成的 `worker.ps1`、`launch.ps1` 均带 UTF-8 BOM，中文/空格路径可解析并正确完成安装或回滚。macOS/Linux 同时确认生成的 shell 助手无 BOM，原位替换与授权交互正常。

1. 私有仓库无 Git HTTPS 凭据时显示访问提示，不出现 Token 表单或交互登录；配置 Git 凭据助手后检查/下载成功。仅 SSH 密钥不能视为 API 授权。测试 Git 未安装、helper 超时、失效/无权限凭据；公开后即使 Git 缺失或凭据失效，也能匿名检查和升级。
2. 启动应用及每 6 小时仅检查，发现新版显示侧栏入口。点击“升级并重启”才下载，无保存对话框；升级过程中展示下载及准备安装状态，切页不丢失进度，重复点击不会启动第二份安装。
3. 断网、磁盘满、摘要/大小错误、解包/签名/内嵌版本错误均不得退出或安装。系统授权取消/超时、助手无法启动时应用继续运行；退出前关闭连接和数据库；助手等待 PID 消失并检查 commit/abort 后才开始替换。
4. macOS Intel/Apple Silicon：普通可写 Applications 与需管理员授权的位置分别验证；应用从 DMG/AppTranslocation 运行时拒绝升级。完成 App 替换并以原用户重启，当前版本更新、配置/凭据/数据库保留；提交失败恢复旧 App，签名与 Gatekeeper 按 M-20 验证。
5. Windows x64/arm64：当前用户安装、需 UAC 目录与便携目录分别验证。Inno 无人值守安装到原目录、不重启系统、不强制关闭其他进程；备份不完整时不能覆盖原安装；安装失败恢复程序目录。以原用户重启。便携版将变为原目录安装版；检查卸载器、快捷方式和用户数据保留。
6. Linux x64/arm64：deb 路径由 dpkg-query 确认，pkexec 授权后安装并保持包数据库一致；依赖/锁失败时正确提示，按 dpkg 恢复。便携包在可写与受保护目录分别验证，同级替换失败恢复旧 bundle。重启工作目录是安装目录，不是随后清理的暂存目录。
7. 重启后核对实际版本与预期一致才确认成功；版本不符或上次失败显示失败并保留恢复目录。成功后普通用户能清理的备份自动回收；受保护位置残留备份需管理员清理。启动后崩溃不具备自动健康回滚，不能记为已验证能力。
8. 中英文、深浅主题、最小窗口检查更新页、新版提示、升级进度和错误；连接关闭提示应在点击前可见。更新逻辑不得写入或导出 Git 凭据，旧 `updates.github_token` 经 ORM 主键迁移删除。

### 2026-10-23 软件更新验证（Step 93）

- 本机通过 Git credential helper 成功访问私有 GitHub Releases API，HTTP 200、最新标签 v1.0.1；不输出、不持久化凭据。未下载真实安装包覆盖用户应用，也未发布新版本。
- `flutter analyze` 无问题；更新网络/配置迁移、升级顺序/失败保护、UI 与全应用中英文布局共 21 项通过。截图 `build/validation/updates/settings-zh.png` 与 `settings-en-dark.png`，已目视确认无 Token 输入、主操作为升级并重启、连接关闭提示在点击前可见。
- macOS `make test-platform` 71 项通过、3 项跳过（P-12 真实 RDP，以及仅 Windows 执行的两个安装助手用例）。P-19 在本机实际运行隔离 Git 凭据助手、POSIX 等待/提交/回滚、macOS zip 签名版本校验及 App 交换，并在本机验证 Linux 使用的便携包/脚本逻辑，不等同 Linux 实机测试。
- Windows/Linux 的 `make test-platform` 与三平台 M-23 系统授权、真实应用安装重启仍待对应实机验证；当前仅有 macOS 环境，跨平台纯逻辑和隔离脚本测试不替代其他系统运行结果。受保护目录备份可能需管理员回收，安装后启动崩溃没有自动健康回滚。

### M-24：SSH 首次连接的瞬时不可达恢复

- 三个平台各执行 `make test-platform`；错误码单元测试在任意平台覆盖三份策略，但不替代对应系统执行。
- macOS 完全退出并重新启动应用，首次连接局域网 SSH（原问题目标 `192.168.0.88:22`），重复数次；验证可直接进入终端。若出现瞬时不可达，日志应记录重试并随后认证成功，不必手动重新打开窗口。
- macOS 本地网络权限尚未确认时接受系统提示后重试；明确拒绝权限或目标持续不可达时，有限重试后仍须显示失败，不把权限拒绝隐藏为成功。
- Windows/Linux 分别在网络刚恢复时连接，确认有限重试；验证真实不可达主机、关闭的 SSH 端口及错误密码不会无限等待或重复认证。
- 三平台检查直连、HTTP/SOCKS5 代理和跳板连接；代理握手/认证错误应立即按原流程返回。代理检测等待期间取消或关闭弹窗，后续迟到的 Socket 应释放。
- 2026-10-23 macOS `make test-platform`：90 项通过、3 项跳过；P-20 在本机覆盖三份错误码策略。定向网络/SSH 端到端回归 40 项通过，相关静态检查通过。Windows/Linux 的 `make test-platform` 和三平台真实网络切换/权限交互待实机验证。


### M-25：RDP 关闭与重连的显示控制协商

1. 三平台分别连接 GNOME Remote Desktop（含系统远程登录重定向）、Windows RDP；建立连接时及重定向过程中调整窗口大小，应可进入桌面，且分辨率最终跟随最新窗口尺寸。
2. 关闭 Tab 后重新连接、退出应用后重新启动连接，各重复三次；服务端不应出现 `Received monitor layout PDU before being able to send capabilities`，连接保持可用。
3. 断开客户端后，从 SSH 检查远端桌面和应用仍在运行（服务器策略允许时）；VNC 两种服务分别检查，勿把服务器会话策略与客户端注销命令混淆。
4. 本次 SSH 只读检查确认 Ubuntu 26.04 / GNOME Remote Desktop 50.0 的原用户会话一直 active，重连日志有上述协议时序违规。VNC 的 TigerVNC 和 GNOME 后台桌面进程也持续运行。未重启服务、未注销远端用户。修复后的真实桌面重连仍需复测；Windows/Linux 的完整 `make test-platform` 待对应环境执行。


### 2026-10-24 RDP 显示控制验证（Step 98）

macOS `make test-platform` 92 项通过、3 项跳过。新增 P-21 的原生 C 时序回归及定向 Dart 分析通过；原生胶水库 arm64、x86_64 均编译成功，macOS Debug 应用编译成功，本机 RDP 连接/剪贴板回归 3 项通过。Windows/Linux 当前没有可用的本项目测试环境，尚未执行 `make test-platform`；三平台使用同一修复，不代表完成三平台实测。真实 GNOME 桌面重连按 M-25 复测。

P-21 补充兼容性用例：服务端能力先于窗口调整到达仍能正常发送；无能力服务端反复轮询不发送布局且连接状态不变。该用例验证发送门控，不模拟完整 Windows 服务端；仍需用修复后的应用执行 M-25，检查 Windows 登录、窗口调整、关闭 Tab 后重连及退出重启后的重连。


### M-26：运行中的构建输出禁止覆盖

1. 三个平台分别执行 `make test-platform`。启动本检出目录构建产物后，再执行 `make` / `make mac`、`make windows`、`make linux`（当前平台）、`make run` 和 `make clean`，应在覆盖或删除应用文件前失败，并提示 PID 与完整路径。Windows 另验证 `windows/run.ps1` 在依赖准备前拒绝继续。
2. 提示后当前应用仍能操作，已有 SSH / RDP / VNC 连接不被终止；正常退出后重试构建应放行。安装目录中的应用、其他检出目录或 `build/validation/` 的独立副本不得误拦。
3. 验证中文/空格路径、Windows 大小写与不同架构目录；配置 Flutter 自定义 build-dir 时，检查应跟随实际输出。进程列表查询失败、超时或同名进程路径无权限时应明确失败，不得继续覆盖。
4. 使用项目 `make` / 版本包装工具构建。直接调用未包装的 `flutter build` / `flutter run` / `flutter clean` 无法由仓库脚本拦截；构建期间也不要另行启动同一输出目录的应用。检查是构建前的进程快照，不是系统级文件锁。`make -j` 可并行准备依赖，但实际 Flutter 构建入口仍会再次检查。
5. 本机 macOS 用独立 bundle id 和数据目录的真实 Debug 副本验证：版本包装入口、`make mac`、`make run`、`make clean` 均以退出码 2 拒绝执行；应用仍存活，原 framework 的修改时间和 SHA-256 均不变，正常退出返回 0。证据：`build/validation/build-guard/live-results.json`。

### Step 101 验证记录（2026-10-24）

macOS `make test-platform`：93 项通过，3 项跳过（已有真实 RDP 与 Windows 专属助手用例）；P-22 内部 12 项 Python 检查通过，包含三份平台实现的解析/错误用例和 macOS 实际进程。版本工具原有回归仍通过，新增 Dart 测试静态检查无问题。Windows/Linux 当前无可用实机环境，尚未执行本轮 `make test-platform` 和 M-26，不能将本机纯逻辑覆盖等同于三平台实测。

### 2026-10-25 Windows x64 全量本机验证

验证提交：`e3c1f58f0c2dd4e70292c25a7d35f11e39e11262`，版本 `1.0.2`。环境为 Windows 11 25H2 x64、Flutter 3.47.7 / Dart 3.13.5、Visual Studio 2022 17.14.41。本机 PATH 原先只有 Python 应用商店别名；本轮在忽略的验证目录准备 Python 3.13.5，设置当前进程 `PYTHONUTF8=1` 并加载 VS x64 开发环境，不修改系统全局设置。

| 验证项 | 结果 |
| --- | --- |
| `make deps` | 通过，保留锁文件，未升级依赖 |
| `make test-platform` | 99 项通过、6 项跳过、1 项失败（P-19 Windows 安装成功路径） |
| `make test` 的客户端部分 | 416 项通过、26 项跳过、1 项失败（同一 P-19）；Make 在客户端失败后停止，服务端另行执行 |
| `server/` 下 `dart test` | 35 项全部通过 |
| 显式启用 `RMK_DSH_E2E=1` | 2 项通过，实际下载 Node.js、安装 dsh、验证 ACP 与模拟模型驱动的终端交互 |
| `make analyze` | 客户端 9 条 info，均为 `curly_braces_in_flow_control_structures`，命令非零退出；服务端另行 `dart analyze` 无问题 |
| `make windows` | 通过，重新编译 RDP / SSH 原生库、Flutter Release、Inno 安装器与便携 zip |
| 构建后 `RMK_REQUIRE_RDP_NATIVE=1 flutter test --no-pub test/platform test/native_crypto_test.dart` | 100 项通过、6 项跳过、1 项失败（同一 P-19）；实际加载新原生库，包含 H.264、生产 C 显示控制与 AES-GCM 回归 |
| `make server` | Windows 默认命令解释器不支持 `mkdir -p dist`，在 Dart 编译前失败 |
| `server/` 下直接执行 Makefile 中的 `dart build cli -t bin/server.dart -o ../dist/remlark-sync-server` | 通过，生成完整服务端 bundle |
| `python3 tools/release/server_bundle.py windows x64 --smoke` | 通过，校验架构、归档、临时中文路径解压、启动服务端并真实读写 SQLite |

P-19 失败已独立复现：`update_platform_windows.dart` 用 `writeAsString` 生成包含中文注释、LF 换行的 UTF-8 无 BOM `worker.ps1`，中文 Windows PowerShell 5.1 按系统编码读取后报告意外的 `}`。相同内容加 UTF-8 BOM 后语法解析通过。失败回滚用例预期退出码本身为 1，其通过结果不能证明助手已执行到安装/回滚逻辑；M-23 仍需修复后验证。本轮只测试并记录，未修改业务或测试代码。

平台跳过项包括未显式授权配置的真实 RDP（P-12），以及只适用于 POSIX/macOS 的安装用例；全量中的其余跳过项还包括 Windows 不支持的本地 SSH/RDP 测试服务端及默认关闭的 dsh 两项（已另行补跑通过）。未访问用户保存的远程主机，未安装或启动桌面应用，未执行真实系统升级/卸载交互。macOS / Linux 本轮没有执行测试，不能用 Windows 结果替代。

产物：`dist/remlark-1.0.2-windows-x64-setup.exe`、`dist/remlark-windows-x64.zip`、`dist/remlark-sync-server-1.0.2-windows-x64.zip`。便携包已检查包含 RDP、SSH 加密、SQLite 与 VC++ 运行库。日志、构建退出码、产物 SHA-256 和脚本解析对比位于 `build/validation/local-full-test-20261025/`。

### 2026-10-25 Windows 更新助手修复验证（Step 109）

修复上述 P-19 的脚本编码故障：Windows x64/arm64 生成的 PowerShell 工作脚本与监督脚本显式带 UTF-8 BOM；macOS/Linux 共用 shell 助手使用同一写入工具并显式不带 BOM。P-19 新增跨宿主编码检查、Windows PowerShell 5.1 真实解析；安装回滚测试检查假安装器运行标记、ready/result 及目标内容，避免语法错误或安装器未启动时误报通过。

Windows x64 构建前 `make test-platform`：102 项通过、6 项条件跳过、0 项失败；构建后设置 `RMK_REQUIRE_RDP_NATIVE=1` 再执行同一入口，仍为 102 项通过、6 项条件跳过、0 项失败。修改文件 `dart analyze`、格式检查与 `git diff --check` 通过。Windows Release 已重新编译；首次打包因当前进程未指定用户目录中的 Inno Setup 路径失败，显式设置 `ISCC` 后用官方独立打包入口成功重建安装器与便携 zip。修复后产物仍位于 `dist/remlark-1.0.2-windows-x64-setup.exe` 和 `dist/remlark-windows-x64.zip`。

日志：`build/validation/local-full-test-20261025/update-fix-*.log`。本轮未重跑客户端全量测试和服务端测试；安装助手专项及完整平台测试已覆盖本次改动。macOS/Linux 和 Windows arm64 本轮没有实机执行 `make test-platform`，须由对应环境或现有 CI 矩阵验证；Windows arm64 生成内容在 x64 上通过编码与语法检查，不代表 arm64 原生运行验证。M-23 的真实 UAC/升级交互仍待手工执行。未修改 Actions 门禁、未提交推送或触发远端 Actions。

### 2026-10-25 Linux x64 全量验证（Step 109）

- 环境：本仓库 Linux x64 主机，Flutter 3.47.7 / Dart 3.13.5；保留锁定依赖，原生编译沿用 `build/validation/linux-h264-env.sh` 的用户态 NASM / libva 开发文件。
- 修复 P-22 的真实进程夹具：本机 `/bin/sleep` 来自多入口 coreutils，复制为 remlark 后按名称分派失败；三平台统一改为隔离 Python 副本，设置 PYTHONHOME，Windows 补 PATH，macOS 保留临时签名。Linux 内部 12 项检查通过，`RMK_REQUIRE_RDP_NATIVE=1 flutter test test/platform` 96 项通过、4 项跳过（真实远端 1、macOS 1、Windows 2）；修改后的夹具仍需在 macOS / Windows 执行。
- 最终全量命令：`RMK_REQUIRE_RDP_NATIVE=1 RMK_DSH_E2E=1 RMK_DSH_E2E_DIR="$PWD/build/validation/dsh-runtime" flutter test --reporter expanded`，426 项通过、11 项跳过；跳过为 macOS SSH 4、按需截图 3、真实 RDP 配置 1、macOS 安装助手 1、Windows 安装助手 2。dsh 复用本地安装目录并检查更新与真实 ACP 交互；本地 SSH / SFTP、RDP 连接 / 剪贴板、原生 AES-GCM、H.264 软件解码、中英文布局和同步场景通过。
- 服务端 `dart test` 35 项通过，`make analyze` 客户端 / 服务端均无问题。仅补齐 13 处条件分支大括号，不改变业务行为。
- `make native-lib rdp-test-server`、`make linux`、`make server` 成功。产物为 `dist/remlark-1.0.2-linux-amd64.deb`、`dist/remlark-linux-x64.tar.gz`、`dist/remlark-sync-server-1.0.2-linux-x64.tar.gz`；服务端通过 `python3 tools/release/server_bundle.py linux x64 --smoke` 的归档、解包启动及 SQLite 读写验证。
- 便携包独立解压，9 个 ELF 文件经 ldd 检查无缺失依赖；`GDK_BACKEND=x11 xvfb-run` 下两次图形启动成功，窗口为 1280×820、最小尺寸 960×640，主密钥跨重启保持一致且权限为 0600。未执行系统安装；不代表干净系统安装、真实远端或 VAAPI GPU 验证。Windows / macOS / arm64 本轮未执行，也未触发远端 CI。
- 日志：`build/validation/current-flutter-tests-final.log`、`current-platform-tests.log`、`current-server-tests.log`、`current-analyze.log`、`current-native.log`、`current-linux-build.log`、`current-server-build.log`、`current-server-smoke.log`、`current-gui-smoke.log`。

### 2026-10-25 v1.0.3 Actions P-22 失败修复（Step 113）

- [运行 40119649487](https://github.com/Remlark/Remlark/actions/runs/40119649487)，提交 `2fc5de3`：Linux 桌面两路及服务端六路通过；Windows x64/arm64 各 97 通过、1 失败、10 跳过，macOS universal 为 94 通过、1 失败、7 跳过。三路均在构建前的 P-22 失败，发布跳过；Node.js 弃用警告不是失败步骤。
- Windows 两路日志均报告 `test_build_and_clean_entry_points` 的 Makefile `read_text()` 使用系统默认 charmap，中文内容导致 `UnicodeDecodeError`。显式按 UTF-8 读取一次并复用文本；不通过全局 Python UTF-8 开关掩盖遗漏。
- macOS 日志报告 `test_real_current_platform_process` 没有抛出预期 GuardError。原始日志未打印 ps 路径与 locale，不能据此确定 runner 内的具体路径变化；本地在 C locale 独立复现 ps 将中文输出为 `M-...` 转义形式、匹配失败。macOS 查询显式指定 UTF-8 子进程环境，测试在默认/C locale 各验证一次存活时阻止构建，且调用方环境不变。夹具采用系统 `/bin/sleep` 的临时签名副本，仅复制字节并设置执行权限，不复制系统受限文件标志；Windows/Linux 继续使用可重命名的 Python 副本。
- macOS 本机 Flutter 3.47.6 / Dart 3.13.5：修复后 `make test-platform` 99 通过、3 条件跳过；P-22 的 12 项检查在系统 Python、Homebrew Python 及 `LC_ALL=C PYTHONUTF8=0 PYTHONCOERCECLOCALE=0` 环境通过；`git diff --check` 通过。三平台纯逻辑测试由同一个 P-22 执行，真实系统检查仅覆盖本机 macOS。
- Windows/Linux 本轮没有可用执行环境，修改后的 `make test-platform` 仍需对应 runner 执行；保留 Actions 三平台构建前后测试门禁。未推送提交、改动版本标签或触发远端运行；原始失败运行尚未转绿。M-26 的真实运行应用保护检查继续按原手工清单执行。

### 2026-10-25 macOS ARM64 进程夹具 SIGKILL 修复（Step 114）

- [后续运行 40123708220](https://github.com/Remlark/Remlark/actions/runs/40123708220/job/120960531259) 已检出修复提交 `582e295`。P-22 此次在启动存活断言报 `AssertionError: -9 is not None : b''`：系统 sleep 副本启动后收到 SIGKILL，还未执行构建保护的路径检查。日志没有系统安全诊断，不能仅凭 -9 确定内核签名校验的具体拒绝原因；上轮 Intel 本地通过不足以证明该副本能在 ARM64 runner 运行。
- macOS 不再复制或重签系统程序，使用现有 Xcode 工具链从 `test/platform/fixtures/build_guard_probe.c` 编译原生普通进程，由链接器处理 ARM64 签名。Windows/Linux 保留 Python 副本，但三平台统一写入就绪标记，并在父进程等待最多 10 秒；程序提前退出时继续报错，不通过跳过测试或放宽存活断言掩盖故障。
- Intel macOS `make test-platform`：99 项通过、3 项条件跳过；P-22 内部 12 项在默认环境及 `LC_ALL=C PYTHONUTF8=0 PYTHONCOERCECLOCALE=0` 环境全部通过。夹具 x86_64 与 arm64 均通过 clang 严格编译，arm64 文件通过 `codesign --verify --strict`。交叉编译和签名验证不等于 ARM64 实际运行。
- 本轮无 ARM64 macOS / Windows / Linux 执行环境，修改后的三平台 `make test-platform` 仍需对应 runner 验证；未提交推送或触发 CI。生产构建保护实现及 M-26 流程本轮未修改。

### 2026-10-25 发布前全量测试工作流与本机回归（Step 115）

本节保留当时的全量回归记录；现行 test* 工作流已按 Step 116 收敛为仅平台专项，不再执行本节描述的客户端全量、dsh 或服务端套件。

- 新增 `.github/workflows/test.yml`：推送 `test*` 标签及手动运行；macOS / Windows / Linux 各 x64、arm64 六路。所有平台锁定 Flutter 3.47.7；每路执行客户端全套（真实 dsh 测试开启）、`make test-platform` 和服务端全套。测试套件独立保留失败结果，矩阵不提前取消。无产品构建、签名凭据、安装包、artifact 或 Release。
- 按 runner、架构及 native 源码哈希精确恢复已有原生缓存，不使用 restore-keys。macOS ARM64 读取原有 universal 键；命中后强制加载 RDP 库，缺失时在 Summary 报告可能跳过的原生/本地 RDP 服务用例。测试进程及小型夹具仍会按需编译。远端 RDP 和截图类用例保留显式配置条件；M-28 需在推送标签后验证。
- 本机环境为 Intel macOS、Flutter 3.47.6 / Dart 3.13.5，复用现有本机原生库和隔离 RDP 测试服务。首次完整客户端测试 462 通过、8 条件跳过；另外启用真实 dsh 下载/安装与 ACP 测试，2 项通过。新增 P-25 四项通过后，`make test-platform` 103 通过、3 条件跳过。服务端全量 43 项通过，两端静态检查及新增测试定向分析通过；YAML 解析、actionlint 和 diff 检查通过。
- 最终统一执行 `RMK_REQUIRE_RDP_NATIVE=1 RMK_DSH_E2E=1 RMK_DSH_E2E_DIR="$PWD/build/validation/pre-release-tests/dsh-runtime" flutter test --no-pub --reporter expanded`：468 项通过、6 项按条件跳过、0 失败，耗时 2 分 36 秒。包含新增 P-25、修复后 P-22、真实 dsh、本地 SSH/SFTP/RDP 与剪贴板、原生 AES-GCM/H.264、客户端及真实服务端同步、中英文布局。剩余跳过为远端 RDP 显式配置 1、Windows 专属安装助手 2、按需截图 3；未通过全量测试访问用户保存的远程主机。
- 日志统一位于 `build/validation/pre-release-tests/`：`client.log`、`dsh.log`、`platform.log`、`server.log`、`client-analyze.log`、`server-analyze.log`、`workflow-analyze.log`、`actionlint.log`。最终包含新增 P-25 和真实 dsh 的合并全量结果另记 `client-final.log`。
- Windows/Linux 和 macOS ARM64 本轮没有本地运行环境；六路实际结果需提交工作流及测试修复后，推送新 test 标签验证。没有推送提交或标签，没有触发远端测试或发布。

### 2026-10-25 test* 工作流仅平台专项（Step 116）

- 工作流更名 Platform Tests，每个 runner 仅执行一次 `make test-platform`，保留三平台各 x64/arm64 六路。移除客户端全量、真实 dsh、服务端测试及依赖准备，不安装本地 sshd 或无关字体；每路超时上限由 60 分钟降为 20 分钟。
- P-25 更名 `platform_test_workflow_test.dart`，校验仅一次平台专项，禁止服务端依赖与其他测试套件加入。精确原生缓存、缺失覆盖摘要及产品构建/发布禁令保持不变，M-28 改为检查专项范围。
- 本机 `make test-platform` 103 项通过、3 条件跳过，耗时 13 秒；修改测试定向静态检查、actionlint、diff 检查通过。日志 `build/validation/pre-release-tests/platform-only.log`。本轮未运行其他测试套件或触发远端 Actions；Windows/Linux 与 macOS ARM64 仍需对应 runner 验证。

### 2026-10-25 Intel macOS 图标像素舍入修复（Step 117）

本节为历史记录；Step 118 已按用户要求删除整个图标自动化测试及 Swift 夹具，以下比较不再执行。

- [test-1.0.3 / macOS x64](https://github.com/Remlark/Remlark/actions/runs/40126292484/job/120968327888)：98 通过、1 失败、7 跳过；失败为 P-14，`actual=[512]`，同密度图标比较 `maxDifference=2`，原阈值为 1。macOS ARM64、Windows 双架构、Linux 双架构均通过，P-22 已通过。本轮失败不再是构建保护进程问题。
- macOS Swift 夹具按全部 RGBA 通道允许最多两个 8 位色阶的栅格化差值；显式校验差值 2 通过、3 拒绝、空数据与不同长度拒绝。刷新前的其他图标必须超出容差，缺失资源仍要求读回像素完全不变。Windows ICO 逐像素核对、Linux 品牌 PNG 字节核对及三个平台生产资源不变；M-19 继续用于实际 Dock / 快捷方式检查。
- 本机 Intel macOS 平台集合 103 项通过、3 条件跳过，耗时 10 秒，包含真实 Swift 刷新和新增边界检查；`git diff --check` 通过。日志为 `build/validation/pre-release-tests/icon-rounding-platform.log`。未重跑客户端全量、服务端或 dsh，未推送或触发 Actions。远端 macOS 15 及其他平台的修改后结果仍需新测试标签验证；重跑旧标签不会带入本次修复。

### 2026-10-25 移除图标自动化测试（Step 118）

- 按用户要求删除 P-14 的 Dart 测试文件和 Swift 夹具，移除三平台资源一致性、系统入口及 macOS 原生图标读回自动化检查；图标外观按 M-12、M-19 手工确认。P-14 编号保留但不再执行，历史测试记录不代表当前覆盖范围。
- macOS `make test-platform` 101 项通过、3 条件跳过，耗时 10 秒；无已删除夹具的代码引用，diff 检查通过。日志为 `build/validation/pre-release-tests/remove-icon-platform.log`。未运行其他套件、未提交推送或触发 Actions；其他平台待新标签验证。

### 2026-10-25 Windows ARM64 zlib 下载校验修复（Step 119）

- [Release 40127434522 / windows-arm64](https://github.com/Remlark/Remlark/actions/runs/40127434522/job/120971764135) 的平台专项通过，服务端 ARM64 作业成功；桌面原生构建在 OpenSSL 编译安装后下载 zlib，System32 tar 报 `Unrecognized archive format`。原始下载文件没有保留，日志只能确定解压输入不可识别，不能直接归因于 ARM64 编译器或某个 HTTP 错误页面。
- 三平台源码下载共用 Python 实现，发送 identity 编码请求、60 秒网络超时、每来源三次尝试；完整 gzip CRC、tar 根目录及可选 SHA-256 均通过才原子替换下载文件，再由对应平台 tar 解压。Windows zlib 1.3.1 用官方 GitHub 和官网双来源，固定 SHA-256；需要的 zlib/FFmpeg 源码在 OpenSSL 编译前准备完成。
- P-26 内部九项检查通过，模拟网络但使用真实 gzip/tar/SHA/临时文件和 CLI；macOS 平台集合 103 项通过、3 条件跳过，耗时 11 秒。定向静态检查、bash 语法及 diff 检查通过。实际获取两个官方来源，均为 SHA-256 `9a93b2b7dfdac77ceba5a558a580e74667dd6fede4585b91eefb60f03b72df23`，新下载工具的真实下载与验证通过。日志 `build/validation/pre-release-tests/source-archive-platform.log`。
- 本轮仅 macOS 执行 `make test-platform`，Windows x64/arm64 和 Linux 的执行及 M-29 构建集成仍需对应 runner。未编译产品、未运行其他套件、未提交推送或触发远端 Actions；重跑旧 Release 标签不会使用新下载脚本。

### 2026-10-25 原生脚本容错与阶段缓存审查（Step 120）

- 查出并修复：源码目录存在即跳过、阶段只看单一库文件、MSYS2/英文编译器资源检查过晚、失败丢失已完成 OpenSSL、仅一份 RDP 库就保存“完整缓存”、旧输出混入新安装、无退避/不复用有效包，以及缓存路径集合不一致可能导致的版本不命中。全部修复在本地验证，没有通过反复触发 Actions 试错。
- P-26 的 19 项检查涵盖下载/解压/发布的失败恢复、慢速响应、错误参数、本地权限、CRC/SHA/目录、缓存复用和非 UTF-8 日志。P-27 的 15 项 Python 检查涵盖阶段产物/配方/目标/位置/缓存身份、混合旧产物拒绝、macOS 双架构、部分进度与 CLI、实际 POSIX 前置失败；另外核对缓存恢复/保存路径集合完全一致。
- 新缓存只保存安装前缀、完成记录和成品库，进度缓存另带已验证压缩包；不复制大型绝对路径编译目录。第三方进度键绑定第三方脚本配方而非全部胶水源文件，完整缓存仍绑定全部 native 源码。两类键均绑定 runner、架构、工作区、校验器和 MSVC；不把未完成依赖当作完整成功。
- 本机 Intel macOS `make test-platform` 106 项通过、3 条件跳过（11 秒）；Python 3.9.6 和当前 Python 通过两套检查，ASCII 严格控制台用例通过。本地 PowerShell 7.6.8 解析脚本，默认/Legacy 模式运行包装器、错目标/缺工具拒绝、实际 Fetch 的多 URL/中文空格路径/缺失源码修复；使用本地文件 URL 和替身编译器，不构建产品。三个真实上游源码包均通过下载、完整性检查及系统 tar 暂存解压。
- 本地 PowerShell 7 并不代表 Windows PowerShell 5.1 + MSVC 实机构建通过；Windows/Linux 的 make test-platform、完整编译和 GitHub 缓存实际保存恢复仍待有环境/额度时按 M-29/M-30 验证，当前未触发。缓存保存适用于普通失败，runner 故障或全局强制取消不能保证执行清理/保存步骤。
- 日志：`build/validation/pre-release-tests/native-audit-platform.log`、`source-faults.log`、`native-state-faults.log`、`source-system-python.log`、`state-system-python.log`、`source-ascii-console.log`、`powershell-wrapper-checks.log`、`powershell-legacy-checks.log`、`upstream-source-checks.log`、`audit-actionlint.log`。下载的本地验证用 PowerShell 放在忽略的 `build/validation/script-audit/`，未修改系统安装。

### 2026-10-25 发布失败保留中转包与网络安装重试（Step 121）

- cleanup 改为仅在 publish 成功后运行，只删除当前运行的中转包；保留期 1 天改为 7 天并允许重跑覆盖同名包，失败后可直接 Re-run failed jobs。
- 新增 `tools/utils/retry_command.py`，release.yml 与 test.yml 的网络安装和 Release 附件上传统一有限重试。
- 本机 Intel macOS `make test-platform` 108 项通过、3 条件跳过；P-24/P-28 Python 检查通过，两个工作流 YAML 解析通过。本机未安装 actionlint。Windows/Linux 的平台测试、M-27 失败重跑和 M-31 需在测试仓库 Actions 上验证。

### 2026-10-25 Windows 中文路径解压与 PowerShell 5.1 哈希修复（Step 122）

- 测试仓库 Release 40136798355 中 Windows x64/arm64 都在构建前的 `make test-platform` 失败。一是 System32 bsdtar 把命令行参数转成 ANSI 代码页，含中文的临时目录变成 `??`，P-26 有 3 项解压失败，真实构建在中文工作目录下也会失败。二是 P-27 的 PowerShell 5.1 由 pwsh 7 启动，继承的 PSModulePath 导致 `Get-FileHash` 无法加载。
- 修复：`prepare_source` 用工作目录定位压缩包，只给 tar 传 ASCII 相对文件名；测试脚本改用 python 计算 SHA-256，保留 UTF-8 BOM。P-26 新增参数断言用例（共 20 项）。
- 本机 macOS `make test-platform` 108 项通过、3 条件跳过；Windows 需在测试仓库重新验证。
