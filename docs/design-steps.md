# Remlark 开发步骤

> 每个 step 完成后在前面标记 [已完成]。新功能 / 模块修改都在本文档追加 step。

## 总体架构

```
lib/
  main.dart                 程序入口
  app/                      应用外壳：依赖容器、主题、主导航
  l10n/                     多语言（中文 / English）
  utils/                    通用工具函数（加密、格式化、平台、对话框、DES 等）
  data/                     drift ORM 数据库与表定义（所有查询均走索引）
  modules/
    hosts/                  主机与分组管理（SSH / RDP / VNC 共用）
    keys/                   SSH 密钥管理（导入 / 生成 ed25519）
    ssh/                    SSH 连接：认证流程、跳板链、HTTP/SOCKS5 出口代理、系统探测
    terminal/               终端工作区：多标签、平铺、广播输入、拖拽上传、右键复制粘贴
    sftp/                   SFTP 浏览器与传输队列（进度反馈）
    snippets/               快捷指令（普通文本 + 特殊动作，如“系统免密登录”）
    sync/                   同步客户端（端到端加密，按 uuid + 更新时间同步）
    ai/                     AI Agent 接口、DeepSeek Harness CLI / OpenAI 兼容实现、聊天、Token 统计
    remote_desktop/         RDP（平台接口：Windows mstsc / macOS&Linux FreeRDP）与内置 VNC 客户端
    import_export/          批量导入导出（JSON、~/.ssh/config）
    settings/               设置
server/                     同步服务端（Dart shelf + drift/sqlite）
```

## Steps

- [已完成] Step 1：工程初始化（Flutter 桌面工程 macOS/Linux/Windows、依赖、Makefile）
- [已完成] Step 2：基础设施（多语言、主题、utils：加密/格式化/平台/对话框）
- [已完成] Step 3：数据库（drift 表：分组、主机、密钥、快捷指令、Agent、聊天会话、聊天消息、Token 用量、设置；全部建立索引）
- [已完成] Step 4：主机管理（分组、分组查看、搜索、协议筛选、主机卡片显示系统图标、编辑对话框）
- [已完成] Step 5：SSH 连接（密码/密钥/记住密码、登录流程：未保存密码弹框、密码错误重新弹框；跳板链；HTTP/SOCKS5 代理；主机指纹确认；系统自动探测）
- [已完成] Step 6：终端工作区（多标签、平铺查看多个会话、广播输入到多个会话、选中复制/快捷键复制、右键粘贴：文本输入/文件上传、拖拽上传、断线重连）
- [已完成] Step 7：SFTP（浏览、上传、下载、新建目录、重命名、删除、传输进度）
- [已完成] Step 8：密钥管理（导入、生成 ed25519、复制公钥）
- [已完成] Step 9：快捷指令（普通文本指令、特殊动作“系统免密登录”，仅 macOS/Linux）
- [已完成] Step 10：同步（服务端 + 客户端；端到端 AES-GCM 加密；自动/手动同步；同步状态显示；从同步服务器删除）
- [已完成] Step 11：AI Agent（Agent 接口、DeepSeek Harness CLI、OpenAI 兼容 API；终端内聊天面板、插入终端选中内容、命令一键发送到终端；Token 速度/输入/输出/上下文；聊天记录查看删除；Token 按天/周/月及模型、Agent 维度统计）
- [已完成] Step 12：远程桌面（VNC：内置 RFB 客户端；RDP：见 Step 17，内嵌 FreeRDP）
- [已完成] Step 13：批量导入导出（JSON 可选加密导出、导入 ~/.ssh/config）
- [已完成] Step 14：设置页（语言、主题、终端字体字号、同步、AI Agent）
- [已完成] Step 15：打包（Makefile：make / make mac / make linux / make windows / make run / make server）

## 补充功能（在原需求外补充）

- 主机指纹首次连接确认（TOFU），指纹变化时警告
- 键盘交互认证（keyboard-interactive）支持
- 终端断线后一键重连
- 终端字体、字号设置
- 主机搜索、最近连接排序
- 从 ~/.ssh/config 导入
- VNC 关联 SSH 主机用于文件传输；RDP 共享“传输目录”用于拖拽传输
- [已完成] Step 16：测试（单元测试：DES、加密、密钥生成、系统探测解析、ssh config 解析；RFB 假服务器测试；
  启动临时 sshd 的端到端测试：密钥登录、两级跳板 + HTTP 代理、SOCKS5 代理、终端 shell、SFTP 传输、密钥被拒回退密码；
  启动真实同步服务器的双客户端同步测试；伪造 dsh 的 AI Agent 测试；UI 快照测试）
- [已完成] Step 17：RDP 改为内嵌实现（不再调用外部 mstsc / FreeRDP 客户端）
  - native/rdp：从源码静态编译 OpenSSL 3.6.5 + FreeRDP 3.32.2，C 胶水库 libremlark_rdp 对外只导出 rmk_rdp_* 接口
  - 胶水库功能：连接线程、GDI 合成 BGRA 画面、键鼠输入、动态分辨率（disp 通道）、证书指纹 TOFU、
    剪贴板（cliprdr：文本双向；本地文件按需提供给远程；远程文件下载到本地后写入系统剪贴板）、
    共享文件夹（rdpdr/drive：\\tsclient\Remlark）、HTTP/SOCKS5 出口代理
  - hook/build.dart：通过 Flutter native assets 自动把库打包进应用（macOS 为 x86_64 + arm64 通用二进制）
  - Dart：rdp_bindings（FFI）、rdp_client、rdp_session、rdp_scancode；VNC 与 RDP 共用 RemoteScreen 渲染组件
  - 测试：FreeRDP 示例服务端（连接 / 证书 / 画面 / 输入）、自写 cliprdr 测试服务端（剪贴板文本与文件双向）

- [已完成] Step 18：布局溢出修复与窗口尺寸
  - 窗口默认 1280x820、最小 960x640（lib/app/window_config.dart，三个平台原生窗口代码同步设置；macOS 记住窗口位置大小）
  - 主机页工具栏窄宽度时协议筛选换行、搜索框伸缩；下拉框长文本省略；终端工具栏信息省略、侧边面板宽度随窗口限制；远程桌面工具栏信息省略
  - 多语言首帧同步加载，避免启动空白帧
  - test/layout_overflow_test.dart：最小 / 默认 / 1920x1080 三种尺寸 × 中英文，渲染所有页面、对话框、会话标签（含侧边面板、平铺、广播），出现任何溢出即失败

## UI 重设计（2026-10-20）

- [已完成] Step 19：使用 ImageGen 交付全部页面、编辑/认证/操作弹窗、上下文菜单及统一控件设计稿；保存在 `docs/ui-redesign/`，由 `index.html` 按页查看，`prompts.json` 保存生成提示词。
- Step 20：按选定设计实施 Flutter 统一主题与共享控件，覆盖全部页面和弹窗，支持中英双语、深浅色主题、键盘与可访问性验证（尚未实施）。
- Step 21：SFTP 改为独立工作区 Tab，左侧本地、右侧远程，底部传输队列；实现目录独立导航、跨侧上传/下载、状态保持与错误处理（本次仅设计，尚未实施）。

## 构建与运行命令

| 命令 | 说明 |
| --- | --- |
| `make` | 按当前平台打包 |
| `make mac` / `make linux` / `make windows` | 分平台打包（需在对应系统上执行，输出到 dist/） |
| `make run` | 运行当前程序 |
| `make test` | 运行客户端与服务端测试 |
| `make gen` | 重新生成 drift ORM 代码 |
| `make server` | 编译同步服务端（dist/remlark-sync-server/bundle/bin/server） |
| `make server-run TOKEN=xxx` | 本地运行同步服务端 |
| `make rdp-lib` | 编译 RDP 原生库（首次约 10 分钟；mac / linux / windows 打包会自动执行） |
| `make rdp-test-server` | 编译 RDP 端到端测试用的服务端 |

## 已知限制

- RDP 原生库在本机（macOS x86_64）编译并测试通过，arm64 为交叉编译未实机运行；Linux（build.sh）与 Windows（build.ps1）脚本已编写但未实际构建验证。
- RDP 暂未启用 H.264（AVC）编码，使用 RemoteFX / Progressive / Planar 等编码；暂不支持声音重定向。
- RDP 远程鼠标指针形状未同步，显示本地指针。
- RDP 远程复制的文件会立即下载到本地（上限 2GB），超过上限不传输并提示。
- 剪贴板测试使用自写的测试服务端，尚未与真实 Windows 服务器联调。
- VNC 剪贴板为 RFB 标准文本剪贴板（Latin-1，兼容 UTF-8 服务器）；VNC 协议没有文件传输标准，文件传输通过“关联 SSH 主机”经 SFTP 完成。
- 终端粘贴 / 拖拽上传无法自动获知 shell 当前目录，上传前会确认目标目录（默认 SFTP 最近浏览目录或用户主目录）。
