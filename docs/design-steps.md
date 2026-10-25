# Remlark 开发步骤

> 每个 step 完成后在前面标记 [已完成]。新功能 / 模块修改都在本文档追加 step。

## 总体架构

```
lib/
  main.dart                 程序入口
  app/                      应用外壳：依赖容器、主导航
    theme/                  调色板 token（AppPalette）、强调色预设、由调色板生成的 Material 主题
    shell/                  主界面外壳与左侧应用导航（含同步状态）
  ui_kit/                   共享控件：页头、导航项、工具按钮、标签、面板、统一弹窗、表格、搜索框、空状态
  l10n/                     多语言（中文 / English）
  utils/                    通用工具函数（加密、格式化、平台、对话框、DES 等）
  data/                     drift ORM 数据库与表定义（所有查询均走索引）
  modules/
    hosts/                  主机与分组管理（SSH / RDP / VNC 共用）
    keys/                   SSH 密钥管理（导入 / 生成 ed25519）
    ssh/                    SSH 连接：认证流程、跳板链、HTTP/SOCKS5 出口代理、系统探测
    terminal/               终端：xterm 视图、拖拽上传、右键复制粘贴、AI 侧栏
    workspace/              工作区：会话标签、广播宫格（≤9）、主机选择器、会话状态栏
    sftp/                   SFTP 独立标签：本地 / 远程双栏、传输队列（进度、取消、重试）
    snippets/               快捷指令（普通文本 + 特殊动作，如“系统免密登录”）
    sync/                   同步客户端（端到端加密，按 uuid + 更新时间同步）
    ai/                     AI Agent 接口、DeepSeek Harness（dsh/：应用内安装、ACP 子进程）/ OpenAI 兼容实现、聊天、Token 统计
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

- [已完成] Step 19：使用 ImageGen 交付全部页面、编辑/认证/操作弹窗、上下文菜单及统一控件设计稿；界面已按设计稿全部实施，设计稿与参考图已删除。
- [已完成] Step 20：按设计稿实施统一主题与共享控件
  - 颜色可配置：`lib/app/theme/app_palette.dart` 定义全部颜色 token（ThemeExtension），提供深色（设计稿默认）与浅色两套调色板；
    强调色以预设形式提供（鼠尾草绿 / 海蓝 / 雾紫 / 琥珀），设置页“通用”可切换；组件只通过 `context.palette` 取色
  - `lib/ui_kit/`：PageHeader / PageFrame（统一页头）、NavTile / SubNav（应用导航、主机分组、设置分区、编辑弹窗分区共用）、
    ToolButton / PillChoice / IconToggleGroup、Tag / StatusText / KeyCap、AppPanel / EmptyState / SearchField / FieldLabel、AppDialog、AppTable
  - 统一页面布局：所有一级页面使用同一页头（标题 + 副标题 + 右侧主要操作），二级导航统一放在页头下方左侧
  - 主机页：搜索、协议筛选、卡片 / 列表视图切换、分组（含“未分组”）、新卡片（地址 / 用户名 / 上次连接 / 同步状态 / 连接按钮）、删除确认带主机摘要
  - 工作区：无会话时完整页头 + 最近连接；打开会话后页头收缩为一行（小标题 + 标签页），最大化内容区；会话底部统一状态栏（地址、状态、连接时长、用户、协议）
  - 终端：工具栏（快捷指令 / 打开 SFTP / AI 助手 / 重新连接）；RDP、VNC 工具栏改为带文字按钮
  - 快捷指令：列表 + 详情（内容复制、自动回车开关、使用说明）；密钥：表格 + 公钥详情（SHA256 指纹）；
    AI：统计卡片、30 天图表、按模型 / Agent 明细（含总计）、聊天记录按日期分组与搜索
  - 设置：左侧分区导航（通用 / 终端 / 同步 / AI Agent / 数据），“标签 + 说明 / 控件”行式布局；同步页状态统计卡 + 配置面板
  - 弹窗：统一 AppDialog（标题与关闭固定、操作栏固定、取消在左），主机编辑弹窗增加分区导航（点击定位、滚动高亮）
  - 侧栏底部同步状态：点击立即同步，未配置时跳转同步设置；默认主题改为深色
- [已完成] Step 21：SFTP 改为独立工作区标签（SftpTab，与终端共用 SSH 连接与传输队列）
  - 左侧本地、右侧远程，两栏独立的后退 / 前进 / 上级 / 刷新 / 路径输入、可排序表格、多选（Ctrl/Cmd、Shift）
  - 中间箭头上传 / 下载选中项；栏间拖动即传输（只接受另一栏拖来的文件，同栏拖动不会触发传输）；系统文件拖入远程栏上传
  - 底部传输队列：进行中 / 已完成 / 失败分类，显示方向、源、目标、进度、速度、剩余时间，可取消、重试、清空已完成、折叠
  - 终端“打开 SFTP”打开或激活对应 SFTP 标签；关闭终端时一并关闭；重连后远程栏自动重新加载
- [已完成] Step 22：广播模式（替代原“平铺 + 勾选广播”）
  - 点击工作区会话栏“广播”进入广播模式：会话不再以标签切换，而是按接近正方形的宫格铺开（列数 = ⌈√n⌉，1→1×1，2→2×1，3/4→2×2，5/6→3×2，7~9→3×3）
  - 广播分组上限 9 个；开启时默认加入当前终端与其他已打开终端（至多 9 个）
  - 顶部广播条显示目标列表（可逐个移出，会话保留为标签）、“添加会话”（选择已打开的终端或新连接 SSH 主机，满 9 个时禁用并提示）、“停止广播”
  - 在任一宫格终端输入，同步发送到分组内所有终端；停止广播后回到标签页视图
  - 广播模式下从主机页新开会话：终端自动加入分组；无法加入（非终端或已满）时自动退出广播并提示，避免新会话不可见
  - 测试：layout_overflow_test 覆盖广播 1~9 宫格、SFTP 标签、主机选择器、设置各分区、浅色主题；ui_snapshot_test 增加工作区 / SFTP / 广播 / 浅色快照

- [已完成] Step 23：修复终端提示符出现在屏幕中间、切页后无法输入、浅色模式终端文字看不清
  - 主因：TerminalPane 的 Stack 未设置 fit，连接成功后状态遮罩返回非定位的 SizedBox.shrink，Stack 在 Row 的宽松高度约束下塌缩为 0 高并居中，终端内容溢出绘制在区域中部，背景色也不生效；改为 `StackFit.expand`
  - 切页无法输入：Stack 高度为 0 时点击无法命中终端获得焦点；另外从其他页面 / 标签切回时由 TerminalPane 监听导航与工作区，在“不可见 → 可见”时把焦点还给终端（不抢 AI 输入框焦点）
  - 浅色模式：终端配色新增“跟随界面”（auto，默认），浅色界面使用浅色终端配色、深色界面使用深色终端配色
  - 附带修复：xterm 4.x 宽度变化 reflow 后不修正 cursorY，导致光标漂移；`terminal/reflow_safe_terminal.dart` 在 resize 前于光标行首放锚点、resize 后按锚点还原光标
  - 测试：terminal_pane_test（已连接终端高度撑满、切页返回后焦点回到终端）；terminal_reflow_test（随机 200 次调整宽高后光标仍在提示符末尾）

- [已完成] Step 24：导航项悬停动画（修复闪烁并重做为明显的浮起效果）
  - 原因：NavTile 的 AnimatedContainer 未悬停色为 Colors.transparent（透明黑），颜色动画逐通道插值，过渡中间帧为半透明灰
  - 方案：未悬停 / 未选中时改用目标色的全透明版本，颜色动画只改透明度
  - 悬停效果重做（浅色侧栏底色与 hover 色几乎相同，原效果不可见）：用 0→1 的悬停进度（180ms，easeOutCubic）统一驱动——背景浮起为面板色并带细边框与轻投影、左侧强调色竖条从 0 伸展到半高、图标与文字右移 3px、图标由弱色变为主文字色；选中项保持强调浅底与满高竖条

- [已完成] Step 25：VNC 支持 macOS 屏幕共享（Apple Remote Desktop 认证）
  - 现象：macOS 未开启“VNC 密码”时只提供安全类型 30/33/35/36，原实现仅支持 None / VNC 认证，报 unsupported security types
  - 实现安全类型 30（`remote_desktop/vnc/ard_auth.dart`）：读取 DH 参数（生成元、素数、服务器公钥）→ 生成客户端密钥对与共享密钥 → MD5(共享密钥) 为 AES-128-ECB 密钥加密 128 字节凭据（用户名 64 + 密码 64，以 0 结尾）→ 回送密文与客户端公钥
  - 协商顺序：填写了用户名且服务器支持 30 时优先使用 macOS 账户认证；否则 VNC 密码 / 无认证；仅剩 30 时也选择它
  - 凭据不足时抛出 RfbPasswordRequired(needUsername)，连接弹窗同时询问用户名（预填主机用户名），填写的新用户名保存到主机配置
  - VNC 主机编辑页显示“用户名”字段，并说明 macOS 填系统账户、标准 VNC 可留空
  - 测试：rfb_client_test 模拟 macOS 服务端（仅提供 30/33/36/35，服务端解密核对凭据），覆盖缺用户名、凭据正确、凭据错误

- [已完成] Step 26：主机编辑页表单布局统一
  - 新增 ui_kit `LabeledField`（上方标签 + 输入 + 下方说明）与 `FieldHelper`；SSH 认证、代理、RDP、VNC 分区全部由浮动标签改为上方标签，与基本信息一致；并排字段顶部对齐
  - “记住密码”移到密码框下方单独一行，说明文字跟在其后
  - 新增 ui_kit `CheckLabel`（紧凑复选框 + 文字，整行可点击），替换全部 CheckboxListTile（其文字与复选框间距过大）
  - 代理、RDP 分区内容改为左对齐

- [已完成] Step 27：远程桌面传输框自动消失、滚轮速度
  - TransferManager 新增 `autoRemoveDoneAfter`：VNC 浮动传输框设为 3 秒，成功任务自动移除，失败任务保留以便查看与重试；SFTP 标签队列不设置，保留历史
  - VNC 浮动传输框在没有任务时整体隐藏（含边框与阴影）
  - 滚轮：新增 `remote_desktop/ui/scroll_accumulator.dart`，按每 20 逻辑像素折算一格（单事件上限 15 格，余数累积），离散鼠标滚轮每事件至少一格；RemoteDisplay.scrollEvent 改为传格数，VNC 每格发送一次 4/5 键按下抬起，RDP 每格发送一次 120 单位
  - 支持触控板双指滚动（PointerPanZoom 事件，原先未处理）
  - 测试：scroll_accumulator_test；ssh_e2e_test 覆盖传输自动移除与失败保留

- [已完成] Step 28：VNC 画面撕裂与拖放上传到目标文件夹
  - 撕裂原因：解码期间到来的帧会在解码回调里补取帧缓冲，此时 RfbClient 可能正在接收下一次 FramebufferUpdate，只更新了部分矩形，取到新旧混合画面
  - 修复：RfbClient 增加 `updating` 标记（接收更新期间为 true）；VncSession.readFrame 在更新中返回 null，更新完成触发 onFrame 后再取帧
  - 拖放目标：新增 `remote_desktop/vnc/finder_locator.dart`，经关联 SSH 主机执行 AppleScript（osascript）获取主屏尺寸、桌面路径与按前后顺序排列的 Finder 窗口（范围 + 文件夹）；把松手位置换算为帧缓冲像素坐标，再按“帧缓冲宽 / 屏幕点宽”换算 Retina 缩放，落在最前的 Finder 窗口则传到该文件夹，否则传到桌面；工具栏“上传文件”传到最前 Finder 窗口（无窗口则桌面）
  - 回退：远程非 macOS、未授权控制 Finder（首次会在远程弹出授权提示）或超时 8 秒，使用主机配置的“默认接收目录”
  - 拖动经过画面时同步移动远程鼠标，便于看清放置位置；上传提示显示实际目标目录
  - RemoteScreen 状态类公开为 RemoteScreenState，提供 `remoteFromGlobal` 换算远程坐标
  - 测试：finder_locator_test（解析、重叠窗口、Retina 换算、无窗口）；rfb_client_test 覆盖更新接收一半时不触发帧

- [已完成] Step 29：VNC 渲染管线重做、拖放上传改为辅助小程序定位
  - 渲染：新增 `remote_desktop/ui/frame_compositor.dart`。RfbClient 记录每次更新的变化区域（Raw / CopyRect / ZRLE），RemoteScreen 只解码变化区域并在 GPU 上一次性覆盖到上一帧（`toImageSync`），所有区域同一时刻读取、整体替换；首帧、尺寸变化或变化面积超过半屏时整屏解码。避免每次小变化都复制并上传整张 4K 帧缓冲导致的积压与延迟
  - RemoteDisplay 接口新增 `frameStable`、`takeDirtyRects`、`readRegion`、`cursor`（RDP 返回整屏刷新、无指针）
  - 指针：声明 Cursor 伪编码（-239，`vnc/rfb_cursor.dart`），服务器不再把指针画进画面、移动鼠标不再触发画面更新；指针由本地按鼠标位置绘制（隐藏系统指针），零延迟
  - 请求流水线：收到更新头即发送下一次增量请求，减少一次往返；尺寸变化后请求整屏
  - 调试：debug 模式每 2 秒输出 `[vnc]`（更新数、矩形数、数据量、各编码）与 `[remote]`（合成次数、整屏次数、平均耗时）统计
  - 拖放定位：SSH 会话内直接 osascript 控制 Finder 会被系统立即拒绝（-1743）且无法弹出授权，原实现吞掉错误回退到配置目录。改为经 SSH 在远程用 osacompile 编译辅助小程序 RemlarkFinder（`~/Library/Application Support/Remlark/`），以 `open -g -W` 在图形会话后台运行，首次运行在远程屏幕弹出“允许控制 Finder”，结果写文件后经 SSH 读回
  - 取消“接收目录”配置：远程为 macOS 时严格按拖放位置（Finder 窗口 / 桌面）上传，无法识别时提示原因（未授权 / 等待授权 / 其他错误）且不上传；远程非 macOS 时上传到主目录
  - 拖入文件时提前建立传输 SSH 连接
  - 测试：frame_compositor_test（首帧整屏、区域合成、不完整时不取帧不丢变化、大面积改整屏）；rfb_client_test 覆盖指针伪编码与编码声明；ssh_e2e_test 覆盖辅助小程序编译、图形会话运行与结果读回

- [已完成] Step 30：运行日志
  - 新增 `utils/app_log.dart`：写入 `<数据目录>/logs/remlark-yyyy-MM-dd.log`，按天切分、保留 7 天；格式“时间 级别 [模块] 内容”；debug 模式同时输出控制台；接管未捕获异常（FlutterError / PlatformDispatcher）；初始化前的日志缓存后补写；超长消息截断；不记录密码、私钥、口令
  - 设置 → 数据 新增“运行日志”：显示日志位置，“打开日志文件夹”按钮；`PlatformUtils.openInFileManager` 统一打开目录（RDP 共享目录复用）
  - 埋点：
    - vnc：TCP 连接、服务器协议版本、安全类型列表与选择、ARD 参数、认证结果、ServerInit（尺寸、名称、像素格式）、声明的编码、整屏请求、尺寸变化、指针形状、剪贴板、不支持的编码 / 消息、接收循环异常与断开；单次更新接收超过 300ms 记“慢更新”（接收 / 等待耗时、矩形数、数据量、编码）
    - vnc.stat（每 5 秒）：更新与请求次数、矩形数、数据量、编码分布、等待（请求→更新头）与接收（更新头→处理完）的平均 / 最大耗时、发送的鼠标 / 键盘事件数
    - remote.stat（每 5 秒）：合成次数、整屏次数、平均 / 最大耗时、增量区域数与面积、合并的更新数、画面不完整跳过次数；单次合成超过 150ms 记“慢合成”
    - finder / upload / transfer：查询耗时与原始输出、拖放点到屏幕点的换算与命中窗口、目标目录、传输排队 / 完成（文件数、字节、耗时）/ 失败
    - ssh、terminal、rdp、sync：连接开始 / 每跳认证 / 成功耗时 / 失败原因、shell 打开与终端尺寸、断开、同步结果
  - 测试：app_log_test（早期缓存补写、格式、截断、过期清理）

- [已完成] Step 31：VNC 本地复制、远程粘贴（经 SSH 写入远程剪贴板）
  - 原实现：每 1.5 秒（及画面获得焦点时）检查本地剪贴板，变化时发送 RFB ClientCutText。macOS 屏幕共享不处理第三方客户端的该消息，且 RFB 标准剪贴板仅支持 Latin-1（中文变为 ?），因此不生效
  - 新增 `remote_desktop/vnc/ssh_clipboard.dart`：配置了关联 SSH 主机时，经 SSH 以 UTF-8 执行 pbcopy 写入远程剪贴板，并 pbpaste 回读核对；仍同时发送 RFB 消息兼容其他 VNC 服务端
  - 关联主机连接失败或远程没有 pbcopy（非 macOS）时，本次连接期间不再经 SSH 尝试，避免反复弹窗；同步加防重入
  - 工具栏开关剪贴板同步改为 `setClipboardSync`，重新开启时立即推送当前剪贴板
  - 日志 [clipboard]：本地剪贴板变化（长度、是否含非 Latin-1）、RFB 发送、SSH pbcopy 耗时与回读结果、失败原因、收到远程剪贴板、开关变化
  - 测试：ssh_e2e_test 经本地 sshd 写入中文剪贴板并核对（结束后恢复本机剪贴板）

- [已完成] Step 32：VNC 文件复制粘贴（双向）
  - 新增 `remote_desktop/vnc/vnc_clipboard_bridge.dart`（剪贴板桥，原 VncSession 内的文本同步迁入），VncSession 只负责转发
  - 本地 → 远程文件：本地剪贴板为文件时，在 VNC 中按 ⌘V 拦截（吞掉 V 抬起与重复）；经 lsappinfo 查询远程最前应用：
    - Finder（或未知）：辅助小程序返回 Finder 插入位置（顶层窗口所在文件夹，桌面活动时为桌面），直接上传到该目录，同名按 Finder 规则改名（“名称 2.ext”），不再补发 ⌘V
    - 其他应用：上传到远程 `~/Library/Caches/Remlark/clipboard/<批次>`，经 JXA 写入远程剪贴板文件 URL，再补发 ⌘V（⌘ 已松开时临时按下）交给该应用；缓存保留最近 5 批
    - 上传发生在按下 ⌘V 时，总是当时的文件内容；粘贴结果为独立副本
  - 远程 → 本地：在 VNC 中 ⌘C / ⌘X 后 600ms、或离开本应用（AppLifecycle inactive）时经 JXA 读取远程剪贴板（changeCount 判断是否有新内容，自己写入的变化忽略）；文件下载到本地 `<数据目录>/clipboard/<批次>` 后写入本地文件剪贴板，由本地 Finder 粘贴到其顶层窗口或桌面；文本直接写入本地剪贴板（解决 macOS 不发送 RFB 剪贴板的问题）；回到本应用时推送本地剪贴板
  - 本地剪贴板为文件时不推送其附带的文件名文本，避免覆盖远程的文件剪贴板
  - 辅助小程序升级为 RemlarkFinder-2（输出 @insertion 插入位置，编译新版本时删除旧版本）
  - 新增 `ssh/ssh_exec.dart`（远程执行 + stdin + 超时），Finder 定位与剪贴板共用；`ShellUtils.uniqueName / basenameRemote`；`SftpService.statEntry`；`TransferManager.upload(asName)` 与 `waitAll`
  - 日志 [clipboard]：本地剪贴板为文件 / 文本、⌘V 拦截、远程最前应用、粘贴目标目录与插入位置、补发按键、远程剪贴板读取（changeCount、文件数、文本长度）、下载与本地写入结果、缓存清理失败
  - 测试：shell_utils_test（改名规则）、finder_locator_test（插入位置）、ssh_e2e_test（经本地 sshd 写入 / 读回远程文件剪贴板与变化计数、查询最前应用、上传改名）

- [已完成] Step 33：根据日志修复拖放定位与鼠标事件洪泛
  - 日志现象 1：Finder 返回插入位置 /Users/…/temp/（说明有窗口），但窗口列表为空，拖放点“未命中 0 个窗口”回落桌面。原因：遍历窗口时 `collapsed of w`（macOS 26 不再支持）等属性出错被 try 吞掉，整个窗口被跳过
    - 修复：辅助小程序升级为 RemlarkFinder-3，去掉 collapsed，按序号取 Finder window，每个窗口单独容错，输出 `@count` 窗口数与 `@error` 错误行（写入日志），解析时忽略这些行
  - 日志现象 2：客户端接收平均 1~12ms、合成平均 1~7ms、无合并积压，客户端处理不是瓶颈；但每 5 秒发送 1195~1733 个鼠标事件（每秒 240~350 个），在服务器端排队导致光标、菜单、拖动滞后
    - 修复：新增 `vnc/move_throttle.dart`，纯移动限流为约 60Hz 且只发最新位置；按键状态变化立即发送并丢弃未发送的移动；滚轮前先同步位置
    - 新增统计“输入→画面”：发出点击 / 按键 / 滚轮到收到下一次更新头的耗时（平均 / 最大），超过 500ms 记警告；vnc.stat 同时显示本地鼠标事件数与实际发送数
  - 测试：move_throttle_test（400 次 / 秒移动限流到约 60 次、最后位置不丢、空闲停止、drop）；dev 依赖 fake_async

- [已完成] Step 34：VNC 撕裂（更新合并）、滚轮洪泛、UI 线程卡顿监测
  - 日志：拖放已命中 Finder 窗口；输入→画面平均 24~65ms（延迟改善）。但每次更新恰好 1 个矩形——macOS 把一次画面变化拆成多个单矩形更新连续发送，逐个呈现即出现新旧混合（撕裂）；另有“发送鼠标 3055（本地事件 7）”，多出的均为滚轮（每格两次指针消息），在服务器端排队；出现一次整屏合成 2825ms，疑似 UI 线程被占用
  - 更新合并：RfbClient 一次更新处理完后等待 4ms，期间有新更新则继续合并，累计最长 50ms 强制呈现；vnc.stat 增加“合并后呈现 N 帧”
  - 滚轮限流：单次事件最多 5 格、每秒最多 60 格，超出丢弃；vnc.stat 显示滚轮格数与丢弃数
  - remote.stat 增加 UI 线程最长卡顿与超过 100ms 的次数（50ms 周期定时器的实际偏差），用于判断是否需要把解码移到后台 isolate
  - 测试：rfb_client_test 覆盖 3 个连续单矩形更新合并为 1 帧

- [已完成] Step 35：VNC 多线程渲染流水线
  - 原实现：网络收发、协议解析、ZRLE 解码、像素复制均在 UI isolate，日志出现整屏合成 2825ms（UI 线程被解码占用）
  - 线程分工：
    - 后台 isolate（`vnc/rfb_isolate_client.dart` 的 rfbWorkerMain）：运行 RfbClient（网络、协议、解码、帧缓冲、连续更新合并），按变化区域（DirtyMerge：面积过半改整屏、过多合并外接矩形）提取像素，打包为一块 TransferableTypedData 零拷贝转给 UI
    - UI isolate：RfbIsolateClient 代理（与 RfbClient 相同的接口与异常），只把区域交给引擎解码并处理输入
    - 引擎 IO / 光栅线程：解码区域图像、GPU 覆盖合成（toImageSync）与渲染
  - 线程间通过消息队列（SendPort / ReceivePort，先进先出）通信；背压：同一时刻最多 1 帧在途，UI 取帧即回执，未回执期间后台把新变化累积在帧缓冲中，回执后一次发送，避免队列无限增长造成延迟累积
  - RemoteDisplay 接口改为 `takeFrame()` 返回完整的 FrameUpdate（整屏或区域列表，`remote_desktop/frame_update.dart`），RDP 返回整屏
  - RfbClient：新更新开始时取消待呈现计时器，保证只在更新完整时通知
  - 日志：AppLog.forward 将后台 isolate 的日志转发到主 isolate（AppLog.raw）写入同一文件；vnc.stat 由后台输出，增加“传给界面 N 帧（整屏）、数据量、打包耗时、等待界面而合并次数”；本地输入统计改为 vnc.input
  - 测试：rfb_isolate_client_test（首帧整屏、仅传变化区域、背压累积与回执后送达、输入经后台发送、认证失败异常映射）；frame_compositor_test 改为基于 FrameUpdate（区域按序覆盖、合并规则）

- [已完成] Step 36：参照 noVNC / TigerVNC 调整滚轮、更新请求与呈现时机
  - 日志：多线程改造后 UI 线程最长卡顿降至 13~15ms、输入→画面平均 11~31ms；但“滚轮 165 格（限流丢弃 671 格）”“245 格（丢弃 1865 格）”——Step 34 的滚轮限流丢弃了大部分滚动，造成滚轮滞后
  - 参考实现：
    - noVNC（core/rfb.js）：WHEEL_STEP=50 像素累积一格，发送后清零，每事件最多一格，不限流；MOUSE_MOVE_DELAY=17ms 移动限流；每次 FramebufferUpdate 处理完 flip 呈现，处理完才发送下一次增量请求（支持 ContinuousUpdates 时由服务器推送）
    - TigerVNC（vncviewer/Viewport.cxx）：每个滚轮事件按方向发送一次按下 + 抬起，不累积不限流；按键状态变化的指针事件立即发送，纯移动按间隔限流
  - 调整：
    - 滚轮：去掉每秒 / 每事件限流与丢弃；ScrollAccumulator 改为 50 像素一格——触控板按 noVNC 规则（满一格发 1 格并清零，每事件最多 1 格），鼠标滚轮每事件至少 1 格、按位移比例多滚（上限 10）
    - 更新请求：由“收到更新头即请求”改回处理完一次更新再请求（尺寸变化时请求整屏），避免服务器在传输中途继续截取产生零碎中间画面
    - 呈现：去掉 4ms / 50ms 定时合并；更新处理完时若网络缓冲中已有后续数据则先继续处理，缓冲读空立即呈现，连续积压超过 50ms 强制呈现；配合“同一时刻最多 1 帧在途”的背压，相当于按帧自然合并
  - 测试：scroll_accumulator_test 按新规则；rfb_client_test 连续到达的更新合并、rfb_isolate_client_test 背压均通过

- [已完成] Step 37：平滑滚轮、ContinuousUpdates、远程复制文件改为粘贴时传输
  - 日志：滚轮每 5 秒 1155~1265 格（本地鼠标事件 0）——高精度 / 平滑滚轮每个事件只有几个像素，“每事件至少一格”使远程滚动过快并在服务器端排队（输入→画面最大 1234ms）；右键菜单出现慢时客户端空闲（UI 卡顿 ≤ 9ms、接收与合成 ≤ 10ms），耗时在服务器响应；远程复制文件后立即下载并显示传输窗口，不符合“粘贴时才传输”
  - 滚轮：位移 ≥ 30 像素视为完整一格（至少 1 格、快速滚动按比例多滚，上限 10）；更小的位移累积满 50 像素才发送
  - ContinuousUpdates（参考 noVNC / TigerVNC）：声明 Fence(-312) 与 ContinuousUpdates(-313) 伪编码；收到 EndOfContinuousUpdates(150) 即发送 EnableContinuousUpdates（整屏，尺寸变化后重新启用），服务器主动推送、客户端不再逐次请求；服务器 Fence(248) 带请求标志时去掉请求位按原负载回应；不支持时日志无“启用推送模式”，仍为请求模式
  - 远程复制文件延迟传输（macOS）：
    - 原生 `LazyFilePasteboard`（MainFlutterWindow.swift，通道 remlark/lazy_pasteboard）：复制时每个文件一个 NSPasteboardItem，声明 public.file-url 并注册数据提供者，私有类型保存远程路径；本地粘贴时系统回调，经通道请求 Dart 下载，等待期间运行主线程消息循环（平台线程与 UI 线程合并），完成后提供本地文件 URL
    - Dart 接口 `vnc/lazy_file_clipboard.dart`（macOS 实现 / 其他平台不支持，回退为复制即下载）；剪贴板桥远程复制文件时只放入占位项并提示“在本地粘贴时传输”，粘贴回调时才下载（此时显示传输进度），同一次复制多次粘贴复用已下载文件
    - 检查本地剪贴板前先判断是否为本程序的占位项（ownsClipboard），避免读取文件触发下载
  - 测试：scroll_accumulator_test（平滑滚轮累积）；rfb_client_test（服务器声明支持后启用推送、不再逐次请求、Fence 回应）；macOS 原生代码经 flutter build macos 编译通过

- [已完成] Step 38：画面残缺（如右键菜单缺一块）的自动校验与修复
  - 现象：右键菜单下半部分正确、上半部分仍为旧画面（桌面背景），疑似某块区域的更新丢失。代码排查未发现确定原因（已验证带偏移视图解码正确），无法区分是服务器未发送、解码错误还是界面合成丢失
  - 后台整屏校验（RfbClient）：`requestVerify` 请求一次非增量整屏；收到覆盖整屏的单个矩形时与更新前的帧缓冲逐像素比对，差异写入 vnc.verify 警告（像素数、范围），5 次更新内未收到整屏矩形则放弃；`idle` 表示帧缓冲已全部交给界面
  - 后台触发（rfb_isolate_client）：更新或输入后空闲 600ms、距上次校验至少 2s、无在途帧且客户端空闲时，先把帧缓冲分块哈希（`remote_desktop/frame_hash.dart`，64×64 分块、RGB 的 FNV-1a）发给界面，再请求整屏校验
  - 界面校验（FrameCompositor）：下一帧携带哈希（FrameUpdate.verifyHashes），应用前读回当前显示的画面（toByteData，哈希在后台 isolate 计算）逐块比对，不一致写入 remote.verify 警告（分块数、范围）
  - 整屏结果照常发送给界面，因此无论原因在哪一环，操作停止后画面都会自动修复；统计中增加整屏校验 / 界面一致性校验次数与发现问题的次数
  - 测试：frame_hash_test（BGRA / RGBA 一致、单像素变化定位到分块）、frame_compositor_test（界面一致性校验计数）、rfb_isolate_client_test（空闲自动校验、发现遗漏像素、界面收到带哈希的整屏修复帧）

- [已完成] Step 39：远程按键卡住（⌘ 卡住导致窗口无法激活）
  - 现象：VNC 中无法激活窗口，连 macOS 自带的屏幕共享也一样。原因：在 VNC 中按下 ⌘（如 ⌘C 复制后 ⌘+Tab 切到本地粘贴），⌘ 的抬起事件被其他应用收到，客户端未通知远程，远程一直认为 ⌘ 按着（服务器全局状态，影响所有客户端），⌘+点击不会激活后台窗口
  - 参考 TigerVNC：失去焦点时释放所有按下的键
  - RemoteDisplay 新增 `displayBlurred()`：RemoteScreen 失去焦点、本应用失去激活（AppLifecycleListener.onInactive）、组件销毁时调用；VNC 发送所有已按下 keysym 的抬起并释放鼠标键，RDP 同样释放扫描码与鼠标键
  - VNC 连接成功后对全部修饰键（Shift / Control / Meta / Alt / Super 左右）发送抬起，清理以往遗留的卡键状态
  - 日志 vnc.key：修饰键按下 / 松开、失去焦点释放的按键、连接后清理
  - 日志同时确认 macOS 屏幕共享不支持 ContinuousUpdates（无“启用推送模式”），仍为请求模式
  - 测试：vnc_key_release_test（真实 VncSession + 模拟服务端：连接后修饰键全部抬起；按住 ⌘ 失去焦点发送 ⌘ 抬起）

- [已完成] Step 40：远程锁屏检测与解锁、传输连接重复建立
  - 现象：远程画面显示桌面但点击无效、窗口均为非激活状态，系统自带屏幕共享显示“已锁定”，关闭 Remlark 后仍如此——远程 Mac 处于锁屏状态（输入由锁屏界面接收，画面仍是锁屏前的桌面）；日志显示锁屏前约 15 分钟 Remlark 未发送任何输入，触发原因待查远程系统日志
  - 锁屏检测：`vnc/remote_mac_state.dart` 经 SSH 读取 `ioreg -n Root -d1 -a` 的 IOConsoleUsers（控制台会话 CGSSessionScreenIsLocked，无需授权），连接后及每 5 秒检查，状态变化写日志
  - 界面：锁屏时在画面上方显示警示条（ui_kit 新增 WarningBar），本次连接使用了登录密码时提供“解锁”（先移动鼠标、按 Shift 唤醒，再输入密码并回车，2 秒后核对；密码只在内存中、不写日志），否则提示在画面中输入登录密码后回车
  - 修饰键诊断：连接时与释放后经 SSH 读取远程修饰键状态（CGEventSourceFlagsState），释放后仍按下时警告
  - 传输连接：prepareTransfer 并发调用（剪贴板、锁屏检查、上传）共用同一次连接，修复每次连接都建立两个 SSH 连接、多余连接不关闭的问题
  - VncKeysym.fromChar / enter

- [已完成] Step 41：远程 Finder 无响应的防护
  - 现象：远程 Finder 窗口灰色、无法点击（浏览器等其他应用正常），关闭 Remlark 后重启 Finder 恢复——与 Remlark 有关；Step 40 的“锁屏”判断有误（检测与解锁功能保留）。客户端日志未显示直接触发点（Finder 卡住前的连接中只有剪贴板读取与一次空文本写入，辅助小程序最后一次调用在其之前且正常完成）
  - 辅助小程序 RemlarkFinder-4：对 Finder 的请求包在 `with timeout of 5 seconds` 中；启动前结束残留实例（已运行的小程序再次 open 只会被激活而不重新执行）；不再 `open -W` 无限等待，改为最多轮询 10 秒结果，超时强制结束并返回 finder.timeout
  - 剪贴板：本地剪贴板为空文本时不再推送（原先会用 pbcopy 把远程剪贴板清空）
  - 测试：ssh_e2e_test 新增“小程序卡住 10 秒超时并被强制结束、不残留进程”；Finder 查询链路测试适配新流程

- [已完成] Step 42：服务器漏报变化的补偿（右键菜单显示一半）
  - 日志结论：整屏校验发现“增量更新遗漏了 110611 / 2660 个像素”，范围正是菜单区域；遗漏处为完整的旧画面而非花屏，判断为 macOS 屏幕共享服务器漏报变化（菜单为独立浮动窗口且有淡入动画），问题发生在数据到达客户端之前
  - 点击后补刷新：鼠标按键变化或滚轮后，于约 120ms 与 400ms 各对指针附近（以指针为中心偏右下、1000×1000，裁剪到屏幕）发送一次非增量区域请求（`RfbClient.requestRegionRefresh`）；第一次尽快消除残缺，第二次覆盖菜单淡入结束后的最终画面；再次点击会取消未执行的补刷新；正常的增量更新不受影响
  - 界面一致性校验误报修正：后台同时发送 3×3 采样点颜色（FrameHash.samples）；界面读回像素同时按 RGBA / BGRA 计算哈希，首次一致即记住读回顺序；仍不一致时日志列出各采样点的期望与实际颜色，区分颜色转换与真正丢失更新
  - vnc.stat 增加“点击后区域补刷新 N 次”
  - 测试：rfb_isolate_client_test 新增“点击后约 120ms 与 400ms 对指针附近补两次完整画面请求”

- [已完成] Step 43：残留补刷新覆盖旧菜单位置、修复整屏校验循环、移除界面比对
  - 日志：残留出现在“上一次右键菜单”的位置（关闭旧菜单时服务器同样漏报“菜单消失”），而补刷新只覆盖当前点击附近；空闲时每 2 秒一次整屏请求（约 6MB）无限循环——整屏校验的结果更新被当作活动又触发下一次校验；界面比对读回全为 #000000（真机 GPU 下读回显示中的图像为空），属误报
  - 点击补刷新：同时覆盖当前位置与上一次按下位置（两者相距超过半个区域时），约 120ms 与 400ms 各一次
  - 整屏校验：只有用户输入（键盘 / 鼠标）算活动，画面更新不再触发；输入停止 400ms 后校验，间隔至少 1.5s
  - 移除界面一致性比对（FrameHash、FrameUpdate.verifyHashes / verifySamples、合成器读回比对）；后台整屏校验保留
  - 测试：rfb_isolate_client_test（远处再次点击时补刷新当前与上一次点击位置；输入停止后整屏校验修复遗漏）

- [已完成] Step 44：点击后的事件驱动补刷新（高亮行先到、菜单重叠部分缺失）
  - 现象分析（用户观察）：右键后 Finder 先把所在行改为高亮背景，再弹出菜单；VNC 中菜单下半部分先出现，与高亮行重叠的上半部分稍后才补上——服务器先发出的高亮行画面不含菜单，菜单更新又未覆盖重叠部分（或截取过早）；客户端发给界面的区域像素均取自最新帧缓冲，重叠部分不会被客户端用旧数据覆盖
  - 事件驱动补刷新：鼠标按键按下 / 抬起后 500ms 内到达的变化区域累积，更新停止 30ms 后对“点击以来所有变化区域”的外接矩形（外扩 16 像素）请求一次完整画面；每次点击最多 3 次，避免补刷新结果再次触发循环；比固定 120ms 更早补上菜单
  - 固定的 120ms / 400ms 指针附近与上一次点击位置补刷新保留（覆盖服务器完全未发送更新的情况，如旧菜单消失）
  - 滚轮（第 4、5 键）不再触发任何补刷新，避免连续滚动时反复请求大区域
  - vnc.stat 显示“其中变化区域补刷新 N 次”
  - 测试：rfb_isolate_client_test（高亮行与菜单先后到达后按外接矩形补刷新、早于 120ms；滚轮不触发）

- [已完成] Step 45：VNC 主机内置 SSH 配置及兼容收尾
  - 添加 VNC 时默认启用共用账户的 SSH，支持独立端口与密钥；可关闭以单独使用 VNC，不再选择其他 SSH 主机。
  - 无损迁移旧关联；不同账户、密码、地址、跳板或代理的旧配置继续兼容，避免编辑时丢失连接。显式关闭内置 SSH 不回退到残留旧关联。
  - 校验端口、SSH 用户名与密钥选择；中英文说明无 SSH 时的能力边界。
  - 连接使用本次 VNC 成功认证的密码；补齐配置迁移、关闭、导出恢复及参数校验测试。

- [已完成] Step 46：将 SSH + VNC 作为同一主机的两个独立连接方式
  - 修正 Step 45 仅将 SSH 当作 VNC 辅助通道的交互；配置顶部明确提供 SSH / SSH + VNC / VNC / RDP，编辑主机可增减连接方式。
  - 双协议主机卡片、列表与右键菜单提供两个连接入口；SSH 打开终端，VNC 打开桌面，共用一条数据库记录与身份。
  - SSH 与 VNC 筛选均包含双协议主机；工作区选择器、广播、跳板支持双协议主机的 SSH 连接。
  - 转换组合时保留各自端口及 SSH 认证、跳板与代理；单独 VNC 不隐式开启 SSH。
  - 更新中英文说明，并覆盖组合切换、连接参数、双入口及双协议布局验证。

- [已完成] Step 47：简化为 VNC 内的“启用 SSH”开关
  - 移除配置顶部的 SSH + VNC 组合选项，仅保留 SSH / VNC / RDP。
  - VNC 选项内开启 SSH 后展开配置，并显示 SSH、VNC 两个独立连接入口；关闭后仅保留 VNC，保留 SSH 参数供再次开启。
  - 沿用双入口、筛选、终端连接和旧数据兼容逻辑，更新中英文说明与回归测试。

- [已完成] Step 48：统一主机卡片连接按钮视觉
  - 将 SSH / VNC 纯文字入口改为终端 / 桌面圆形图标按钮，与单连接箭头统一尺寸和轮廓。
  - SSH 使用浅底描边、VNC 使用实心强调色；间距 8px，卡片 40px，列表 32px。
  - 保留独立连接行为，加入中英文悬停说明和无障碍名称；验证按钮动作及明暗主题截图。

- [已完成] Step 49：拆分主机协议标签
  - 将卡片、最近连接与列表中的 SSH + VNC 合并标签改为并排的 SSH、VNC 标签，分别沿用协议颜色，间距 6px。
  - 共用协议标签组件，单协议主机继续显示单标签。

- [已完成] Step 50：统一终端按钮背景与悬停反馈
  - SSH、VNC 与箭头连接按钮共用实心强调色，移除 SSH 的浅底描边差异。
  - 显式设置悬停/聚焦与按下的颜色叠加、手形鼠标，明暗主题均有清晰反馈；快照验证实际鼠标悬停。

- [已完成] Step 51：修复大窗口下视图切换按钮偏离右侧
  - 搜索与协议筛选合为 Expanded 左侧组，移除与松约束搜索框竞争空间的 Spacer。
  - 视图切换始终保持页面右边距 24px，筛选与搜索保持 16px 间距。
  - 回归验证从 764px 放大到 3840px 再缩小时的对齐与无溢出。

- [已完成] Step 52：统一单协议与多协议连接图标
  - 单独 SSH 使用终端图标，单独 VNC / RDP 使用桌面图标；多协议按同一规则显示按钮。
  - 卡片、最近连接、列表共用圆形强调色按钮与悬停反馈，移除单协议的箭头及列表中的特殊按钮样式。
  - 按协议显示中英文连接说明，补齐 RDP 文案。

- [已完成] Step 53：第三版工作区工具组与混合协议网格
  - 顶部保持一行：标签、新建会话、独立广播、最右侧布局菜单；没有 SSH 时隐藏广播。
  - 支持选择 SSH/VNC/RDP 组成最多 9 格的独立输入网格；标题栏双击或放大图标聚焦，返回网格恢复选择。
  - 保持会话视图身份，切换布局不重新挂载终端与远程桌面；紧凑网格收起内部工具栏。
  - 广播目标与布局分别管理，只接受 SSH；新增会话不自动参与，广播期间禁用布局，停止保留排列。
  - 补齐中英文；验证混合网格、广播输入隔离、关闭清理、视图保留及不同尺寸无溢出；保存原生 Flutter 快照供视觉验收。

- [已完成] Step 54：清理 VNC 调试日志
  - 删除 vnc.stat / vnc.input / remote.stat 周期统计及其计数器、UI 线程卡顿探测、慢更新 / 慢合成 / 输入延迟告警。
  - 删除协议握手逐步跟踪、Fence / 指针形状 / 整屏校验比对等 debug 日志；整屏校验保留（仍用于修复漏报画面），去掉逐像素比对。
  - 删除仅用于诊断的远程修饰键状态查询（SSH 读取 CGEventFlags），连接后仍释放全部修饰键。
  - 精简剪贴板与 Finder 定位的过程日志；保留连接、认证、锁屏、断开等生命周期日志以及所有警告和错误日志。

- [已完成] Step 55：SSH 原生加密，修复 SFTP / VNC 文件传输仅约 1MB/s 且传输时界面卡顿
  - 原因：dartssh2 默认优先 aes-gcm，其纯 Dart GCM 实现约 1MB/s，且加解密运行在 UI 线程。
  - 新增原生库 native/ssh_crypto（libremlark_crypto，静态链接 RDP 构建产出的 OpenSSL），提供 AES-GCM；hook/build.dart 打包为 `crypto` 代码资源，Makefile 新增 crypto-lib / native-lib。
  - dartssh2 改为内置副本 third_party/dartssh2，补丁：`sshAeadBackend` 可注入；lib/modules/ssh/crypto/native_crypto.dart 以 FFI leaf 调用注入（typed data 直接传指针，无额外拷贝）。
  - SshConnector：原生库可用时优先 aes-gcm，否则优先 chacha20-poly1305，aes-gcm 兜底。
  - SFTP 读写请求由 16KB 改为 64KB；传输进度通知限频 100ms，避免每秒上千次界面重建。
  - 验证：原生与纯 Dart GCM 结果逐字节一致、篡改标签认证失败（test/native_crypto_test.dart）；本机 sshd 实测 SFTP 由约 1MB/s 提升到上传约 90MB/s、下载约 105MB/s。

- [已完成] Step 56：RDP 只传输变化区域
  - 原因：每帧都把整屏画面（1920×1080 约 8MB）在 UI 线程上拷贝三次（原生拷出、Dart 再拷、引擎解码），与变化大小无关。
  - 原生库在 EndPaint 时累积变化区域（相交 / 相邻合并，最多 16 块，超限合并为外接矩形，超过半屏改整屏）；`rmk_rdp_take_frame` 替代 `rmk_rdp_copy_frame`，只拷贝变化区域。
  - Dart 侧 leaf 调用直接写入 Uint8List（先查询大小再取，期间有新变化按新大小重试），按区域生成 FrameUpdate，与 VNC 共用分块合成。
  - 验证：rdp_e2e_test 首帧整屏、鼠标移动后只取到变化区域且覆盖后画面正确、无变化时返回空。
- [已完成] Step 57：VNC 画面静止后补刷新（修复菜单 / 通知残留）
  - 依据：日志中整屏校验 25 次发现增量更新漏掉的像素（菜单栏下方通知横幅区域、菜单位置），服务端未发送动画的最终状态。
  - 新增 vnc/settle_refresher.dart：记录所有增量变化区域，画面静止 250ms（输入后 0.5 秒内为 30ms）后对外扩 16 像素、相交合并后的区域请求完整画面；补刷新结果 1 秒内落在已补刷新区域内的变化不再记录，防止循环。取代原先仅在点击后 0.5 秒内生效的补刷新；点击处的固定补刷新与空闲整屏校验保留。
  - 验证：settle_refresher_test（静止后补刷新、持续变化不刷新、相交合并、防循环、输入后加速、大面积整屏）；rfb_isolate_client_test 高亮行与菜单都被补刷新覆盖。

- [已完成] Step 58：文件拖放只由可见的窗口接收
  - 问题：同时打开 SSH 与 RDP 时，拖文件给 RDP，SSH 也开始上传。desktop_drop 的 DropTarget 全局监听、只按坐标判断，隐藏的会话（工作区 Offstage）、隐藏的页面（IndexedStack）、对话框下层的组件都会收到。
  - 新增 ui_kit/file_drop_target.dart：仅在 `Visibility.of`（综合所有祖先）为真且所在路由为当前路由时启用；终端、SFTP、VNC、RDP 四处拖放统一改用。
  - 工作区隐藏会话由 Offstage + TickerMode + ExcludeFocus 改为等价的 `Visibility(maintainState: true)`，以提供可见性作用域。
  - 验证（test/file_drop_target_test.dart，模拟原生拖放事件）：对照组复现原问题；RDP 与 SSH 叠放、多个 SSH 标签切换、VNC / SFTP / 多 SSH 混合、网格各格、切到其他页面、对话框遮挡、拖动中被隐藏回调离开。

- [已完成] Step 59：RDP 拖放直接粘贴到松手处
  - 问题：拖入 RDP 的文件只放入 \\tsclient\Remlark 与远程剪贴板，需手动 Ctrl+V；拖放提示在白色画面（如资源管理器）上难以辨认。
  - RDP 只传输画面与输入，无法查询远程窗口 / 文件夹（Windows 的 SSH 会话与桌面不在同一会话），改为“激活 + 粘贴”：
    原生剪贴板模块在服务端确认格式列表时发出 RMK_EV_CLIP_READY；dropFiles 收到确认后在松手处单击激活窗口，再发送 Ctrl+V（超时 2 秒则只提示手动粘贴）。拖动经过时同步移动远程鼠标。
  - 拖放提示：画面整体压暗 + 主题配色卡片（图标 + 文字）+ 强调色边框，任意背景下可辨识（VNC / RDP 共用）。
  - 验证：rdp_clipboard_test 写入文件剪贴板后收到就绪事件。

- [已完成] Step 60：精简远程桌面提示
  - 删除成功时的说明性提示（RDP：已发送 / 已粘贴 / 远程文件已就绪；VNC：正在粘贴 / 正在从远程复制 / 已复制 / 已拉取 / 已开始上传），只保留失败提示；传输进度见传输列表与状态栏。
  - RDP 拖放提示精简为「松开粘贴到鼠标所在的文件夹」，与 VNC 一致。

- [已完成] Step 61：DeepSeek Harness 改为应用内安装、ACP 子进程运行
  - 运行环境抽象为 `AgentRuntime` 接口 + `AgentRuntimes` 注册表（按 Agent 类型），dsh 为第一个实现；后续其他需要本地安装的 Agent 实现同一接口。
  - 安装入口在添加 / 编辑 Agent 框：选择 DeepSeek Harness 时检测，未安装则框内先安装（显示阶段与 Node.js 下载进度，安装完成前不能保存，关闭框不中断安装）；已安装时可「更新」/「检查更新」。
  - 检测更新只在编辑框中进行；Agent 列表只读本机安装状态（不联网），副标题显示未安装 / 正在安装；删除最后一个 dsh Agent 时可勾选同时移除运行环境（保留会话记录）。
  - 安装器：下载 Node.js LTS（SHA-256 校验）→ 私有 npm 安装 `@deepseek-ai/dsh` → 验证后整目录替换；平台差异封装为 `DshPlatform`（macOS / Linux / Windows 各自实现）。
  - Agent：由每次提问启动 `dsh --profile headless` 改为常驻 `dsh --profile acp` 子进程（ACP JSON-RPC），会话新建 / 续问 / 恢复，可选模型，取消，权限请求自动拒绝。
  - Agent 编辑框去掉「命令路径」「参数」，模型改为可选（留空用 dsh 默认模型）；新增工具 `utils/version_utils.dart`、`utils/download_utils.dart`。
  - 测试：内存假 ACP Agent 的单元测试；真实下载安装并启动 ACP 的端到端测试（`RMK_DSH_E2E=1` 时运行）。

- [已完成] Step 62：dsh 只操作当前终端的服务器（MCP `run_command` 方案已由 Step 64 替代）
  - 关闭 dsh 的本机工具（启动补丁），改为应用提供的 `run_command` 远程工具：经该终端的 SSH 连接另开 exec 通道执行，通过本机 MCP 服务（127.0.0.1 + 随机令牌）挂载到 dsh 会话。
  - 每条命令在聊天面板确认（拒绝 / 执行，可勾选本次对话自动执行），确认最多等 40 秒（dsh 的 MCP 调用 60 秒超时）。
  - 每个终端标签页一个聊天，切换回来继续原对话；dsh 会话绑定该终端的工具入口，换入口时关闭后重新挂载；在其他服务器的终端载入历史记录时新建 dsh 会话。
  - 检测更新只在 Agent 编辑框中进行，Agent 列表只读本机安装状态。
- [已完成] Step 63：聊天底部的命令权限设置（确认方式已由 Step 64 改为在终端按回车）
  - 「附带终端输出」旁新增权限选择：只给建议 / 逐条确认（默认）/ 只读自动执行 / 全部自动执行；每个终端标签页独立，「全部自动执行」以警示色显示。
  - 只读命令判断 `ai/tools/read_only_commands.dart`（保守白名单）；确认卡片去掉「本次对话自动执行」勾选框，改由权限选择控制。
  - 切换模式即时作用于排队中的命令；开启 / 关闭工具时会话重新挂载并在本轮提问中告知模型。
  - 测试：四种模式的放行规则、只读命令判断正反例、只给建议不挂载工具及中途开启。
  - 测试：MCP 服务鉴权与调用、命令确认（拒绝 / 超时 / 断开 / 自动执行）、会话入口重绑定、跨服务器载入历史；真实 dsh + 假 Anthropic 模型服务的端到端测试（本机工具已关闭，run_command 经 MCP 执行）。
- [已完成] Step 64：AI 通过 JSON 协议直接操作终端（替代 MCP 工具方案）
  - 原因：dsh 的 MCP 工具调用固定 60 秒超时，apt 安装等长命令会被中断；另开 exec 通道也无法保留 cd / export 等终端状态。
  - 新增 `ai/terminal_agent/`：协议（run / wait / answer）、步骤执行（持续记录输出、按停顿汇报）、权限模式、只读判断、`TerminalDriver` 接口；终端模块 `TerminalAgentDriver` 实现（直接写入 shell，不经广播），`TerminalSession` 新增输出流与用户输入流。
  - 命令输入用户眼前的终端，结果交回 Agent，直到 Agent 在聊天中回答；命令是否结束由 Agent 判断；终端完全由用户控制（卡住时用户自己输入，AI 操作期间不限制输入）。
  - 逐条确认改为「填入终端不回车，用户按回车执行 / Ctrl+C 放弃」；删除 MCP 服务、`run_command` 工具、命令确认卡片。
  - 新增 `utils/ansi_utils.dart`（终端输出转纯文本、保留末尾）。
  - 上下文：同一聊天内所有步骤共享上下文（dsh 同一会话；OpenAI 兼容 API 每步重新带上整个对话，AI 回复保留原始 JSON）。
  - 测试：协议解析、终端输出清理、四种权限下的执行流程（自动回车 / 等待回车 / Ctrl+C / 只读判断）、长命令 wait 与思考期间输出不丢、停止、普通问题直接回答、跨服务器载入历史；真实 dsh + 假模型服务的端到端测试。
- [已完成] Step 65：修复 AI 已回答但聊天中没有显示
  - 现象：执行两步命令后任务直接结束，聊天中没有回答。dsh 会话日志显示模型已回复 answer，但 Remlark 收到「提问结束」时该轮文本为空（token 记录输出为 0）。
  - dsh Agent 在提问结束后继续接收迟到的更新再结束本轮，迟到更新写日志；终端循环收到空回复时重新提问一次，仍为空则提示用户。
  - 关闭 dsh 的网络搜索 / 抓取、todo、goal、skill、计划模式工具（日志中两次提问调用了 12 次无关工具，包括搜索无关新闻）。
  - 测试：先结束后送达回答、空回复重试与提示。
- [已完成] Step 66：终端上传进度显示在 SSH 状态栏
  - 问题：终端拖拽 / 粘贴上传与 SFTP 标签共用一个传输队列，进度只能在 SFTP 页面看到，且混在 SFTP 的上传列表中。
  - `TerminalSession` 新增独立的 `uploads` 传输管理器（与 SFTP 标签的 `transfers` 共用同一 SFTP 连接，队列分开），成功的任务 3 秒后自动移除；SFTP 页面不再显示终端发起的上传。
  - 终端状态栏右侧新增 `terminal/ui/upload_status.dart`：上传中显示文件名、剩余排队数、进度条、百分比与速度；结束后显示“上传完成”或“N 项上传失败”；点击弹出上传详情（取消、重试、移除）。去掉“已加入上传队列”的提示。
  - `TransferManager` 新增 `remove`；`TransferList` 的失败 / 已取消任务增加重试与移除按钮（VNC 浮动传输框同样可用）。
- [已完成] Step 67：终端右键菜单
  - 原右键行为为“有选区直接复制、无选区直接粘贴”，没有菜单，用户不易察觉。
  - 改为在点击位置弹出菜单：复制（有选区时可用）、粘贴（剪贴板为文件时显示“粘贴并上传（N 项）”，走终端上传流程）；右侧显示对应快捷键；未连接或剪贴板为空时粘贴不可用。
  - 远程程序开启鼠标上报（vim、tmux 等）时右键仍交给远程程序。
- [已完成] Step 68：统一下拉菜单与右键菜单
  - 问题：菜单分别使用 showMenu、MenuAnchor、PopupMenuButton、DropdownButton(FormField)，带展开动画显得慢，宽度与位置各不相同（有的不在按钮下方）。
  - 新增 `ui_kit/app_menu.dart`：`AppMenu.showAt`（右键菜单）、`AppMenuAnchor`（按钮下拉）、`AppDropdown`（选择框，外观与输入框一致，支持无边框样式）；菜单项支持图标、说明、快捷键、危险色、禁用与选中勾。
  - 无动画；下拉菜单左对齐触发控件并显示在其下方（下方放不下时在上方），选择框菜单与选择框等宽，按钮菜单不窄于按钮；右键菜单超出屏幕时向左 / 向上翻转；点击外部（含右键）或 Esc 关闭，方向键切换、回车选中。
  - 替换全部 16 处：主机卡片 / 分组 / SFTP 文件 / 终端右键菜单，新建主机、添加跳板机、工作区布局、AI 命令权限下拉，以及片段类型、终端主题、同步间隔、AI Agent、分组、密钥、认证方式选择框。
  - 测试：`test/app_menu_test.dart` 验证一帧内显示、等宽左对齐、右键菜单翻转、外部点击关闭与回调。
- [已完成] Step 69：广播固定以网格展示广播目标
  - 问题：开启广播只同步输入、不改变布局，单窗口下只能看到一个终端。
  - 广播期间 `showingGrid` 固定为 true，画布展示 `displayedGridSessions`（广播目标）；用户保存的网格选择与单窗口/网格状态不变，停止广播后恢复原布局，当前会话不在网格内时切到网格第一个。
  - 广播期间标签栏只能在目标间切换输入焦点，新开会话在后台打开；布局入口显示为网格并禁用。
  - 删除默认快捷指令 `df -h`、`top`（只影响首次启动）。
- [已完成] Step 70：密钥页同步显示其他位置新建的密钥
  - 问题：密钥页常驻于 IndexedStack，只在首次创建时加载列表；在主机编辑器中生成 / 导入的密钥（以及同步、导入数据写入的密钥）不会出现，需在密钥页再操作一次才刷新。
  - `KeyRepository` 改为 ChangeNotifier，保存、删除后通知；密钥页监听并重新加载。
  - 测试：`test/key_repository_test.dart` 验证保存与删除都会通知。
- [已完成] Step 71：接入 Codex Agent
  - 参照 GitAstra 的 Codex 接入：应用内从 GitHub Releases 下载完整运行包（SHA-256 校验、验证后整目录替换），以 `codex app-server` 子进程（stdio JSON-RPC）运行；每个 Agent 独立 CODEX_HOME，可登录不同 ChatGPT 账号。
  - 对接现有接口：`AgentKind.codex`、`CodexAgent implements AiAgent`（线程续接 / 恢复 / 中断、流式回答与推理、真实 token 用量）、`CodexRuntimeController implements AgentRuntime`（安装 / 更新 / 移除），在 `AgentFactory` 与 `AgentRuntimes` 注册；终端操作沿用 dsh 的 JSON 协议：终端输出作为下一轮提问发给 Codex，Codex 回复的命令由 Remlark 输入终端。
  - 关闭 Codex 的本机命令、插件、子 Agent、网络搜索等功能，线程只读、不请求审批，Codex 不碰用户的电脑。
  - 设置页：Agent 编辑框新增 Codex 类型，显示运行环境状态、账号（登录 ChatGPT / 退出登录，登录中可取消或复制链接）与模型下拉框；模型在打开时与登录完成后自动刷新，可手动刷新。放弃新建或删除 Agent 时删除其 CODEX_HOME（`AgentRuntime.removeAgentData`）。
  - 公共化：dsh 的 ACP 连接改为 dsh 与 Codex 共用的 `runtime/json_rpc_connection.dart`（`JsonRpcConnection`）；解压改为公共的 `utils/archive/ArchiveExtractor`（各平台实现）；新增 `PlatformUtils.openUrl`。
  - 测试：`test/codex_agent_test.dart`（假 app-server：新线程参数、流式输出与用量、续问 / 恢复 / 恢复失败附历史、未登录提示、取消中断、账号与模型）、`test/codex_installer_test.dart`（本地 HTTP 模拟发布：安装、升级、校验失败保留旧版本、移除）；截图 `09_agent_dialog_codex`。已用本机真实 codex 0.162.1 验证启动参数、模型列表、`thread/start` 参数与登录链接获取。
  - 尚未验证：登录后真实对话（需要 ChatGPT 账号登录）；Windows / Linux 安装流程未实机验证。
- [已完成] Step 71.1：修复 Codex 刚安装后报 “failed to initialize sqlite state runtime”
  - 原因：编辑框同时读取账号与模型，在新的 CODEX_HOME 上同时启动两个 app-server，同时初始化 sqlite 状态库，其中一个失败（用真实 codex 0.163.0 复现）。
  - 修复（参照 GitAstra 的做法）：编辑框先读账号、再读模型，不同时启动进程；登录改为在临时 CODEX_HOME 中进行，成功后 `adoptLogin` 只替换凭据文件，登录进程不占用 Agent 自己的目录。另外 `CodexAppServer.open` 按 CODEX_HOME 排队启动作为兜底（聊天窗口读取模型时可能与其他操作同时发生），前一个握手完成后再启动下一个；启动后仍可同时运行。测试：`codex_agent_test.dart` 验证启动不重叠（去掉排队时失败），并用真实 codex 在新目录上连续 5 轮同时打开 3 个进程均成功；`codex_installer_test.dart` 验证采用登录只替换凭据、删除临时目录；真实 codex 验证登录中临时目录存在、取消后被删除。
- [已完成] Step 72.5：修复退出时崩溃
  - 现象：从 Dock 退出时弹出崩溃提示。崩溃报告（DiagnosticReports/remlark-*.ips）显示 EXC_BAD_ACCESS @ 0x0：引擎关闭时数据库所在的后台 isolate 被直接销毁，sqlite 语句的清理回调（`sqlite3_finalize` / `sqlite3_changes`）在连接释放后运行。
  - 修复：`main.dart` 注册 `AppLifecycleListener.onExitRequested`，退出前调用 `AppServices.shutdown()`：停止自动同步、关闭所有会话、结束 dsh / Codex 子进程，最后关闭数据库；每步限时 3 秒并忽略错误，退出不会卡住。日志记录“退出：释放资源”。
- [已完成] Step 72.4：OpenAI 兼容 API 去掉 DeepSeek 默认值并统一名称
  - 去掉默认接口地址 https://api.deepseek.com 与默认模型 deepseek-chat（及输入框占位）；API 地址与模型都填写后才能保存，未配置时提问直接提示（不发请求），“获取列表”在未填地址时提示先填写。
  - 名称统一为“OpenAI 兼容 API / OpenAI-compatible API”（`AgentKind.label`），用于新建 Agent 默认名称、类型切换、Agent 菜单与设置列表。
  - 测试：`openai_models_test.dart` 新增无地址、无模型时直接报错。
- [已完成] Step 72.3：聊天布局、Agent 绑定、OpenAI 模型列表、删除终端字体设置
  - 删除“附带终端输出”开关：终端当前屏幕在所有权限模式下自动附上（原来只给建议模式下不附），选区仍单独附带。
  - 布局：Agent / 模型 / 推理强度移到输入框上方工具栏（原开关位置），与命令权限同一行；顶部显示当前聊天标题。Agent 菜单名称与类型相同时不重复显示类型；空间不足先截断模型名。
  - 切换 Agent：当前聊天已有消息则新建对话（聊天绑定开始时的 Agent，换 Agent 无法命中上下文缓存），其他终端标签的聊天不受影响。
  - OpenAI 兼容 API：设置页模型框右侧「获取列表」读取 `/models` 后弹出选择（可直接输入），API Key 可切换显示、提示本地服务可留空；聊天中也可从模型列表选择，推理强度固定为默认。
  - 删除终端字体设置（手动输入字体名体验差）：终端固定使用系统等宽字体（macOS 为 Menlo），旧配置忽略。
  - 测试：`openai_models_test.dart`（地址处理、/models 读取与认证、聊天可选项）、`ai_agent_test.dart`（只给建议也附屏幕、聊天绑定 Agent）、截图测试中验证切换 Agent 新建对话；截图 `09_agent_dialog_openai`、`09_terminal_ai_agent_menu`。
- [已完成] Step 72.2：聊天改为 ⌘Enter / Ctrl+Enter 发送
  - 单独按 Enter 经常误触发送：改为 ⌘Enter（macOS）/ Ctrl+Enter（Windows、Linux）发送，Enter 换行；输入框提示按平台显示快捷键。
  - 测试：`chat_send_key_test.dart`（快捷键判断）；截图测试中验证 Enter 不发送、Ctrl+Enter 发送。
- [已完成] Step 72.1：Agent 改在聊天窗口中切换
  - 聊天窗口顶部改为一组紧凑下拉菜单：Agent、模型、推理强度；Agent 菜单列出全部 Agent（附类型），底部「管理 Agent…」跳到设置页。输入框上方工具栏恢复为附带终端输出、命令权限与选区提示。
  - 设置页 AI Agent 去掉“当前使用”单选与标签，只负责添加、编辑、删除；说明文字改为“使用哪个 Agent 在聊天窗口中切换”。
- [已完成] Step 72：聊天窗口切换模型与推理强度
  - 每个 Agent 保存自己的模型与推理强度：`AgentSettings.reasoningEffort`，数据库 schema 1 → 2 新增 `agent_configs.reasoning_effort`（迁移保留旧数据，默认为空 = 模型默认）。
  - `AgentRuntime.loadOptions` 读取可选模型与推理强度（`runtime/agent_options.dart`），`AgentOptionsController` 按 Agent 缓存。dsh 从会话配置项读取（模型 + off/low/high/max），Codex 从 `model/list` 读取（每个模型不同）；OpenAI 兼容 API 不支持，推理强度固定为默认。
  - 聊天窗口：输入框上方工具栏新增模型、推理强度两个紧凑下拉菜单（原选区提示改为“附带终端输出”的悬停说明）；切换模型时不支持的推理强度改回默认；模型菜单可刷新列表；回答中不能切换。
  - 生效：dsh 每轮提问前按配置 `session/set_config_option`（中途切换立即生效，改回默认时恢复会话默认值）；Codex 每轮 `turn/start` 带上 model 与 effort。
  - 设置页 Codex 编辑框：模型旁新增推理强度下拉框；保存 Agent 时保留聊天中选择的推理强度；编辑或登录状态变化后丢弃缓存。
  - 测试：`database_migration_test.dart`（schema 1 → 2）、`ai_agent_test.dart`（dsh 可选项与缓存、每轮切换推理强度 / 改回默认 / 中途换模型）、`codex_agent_test.dart`（effort 传入与默认不传、模型推理强度解析）；截图 `09_terminal_ai_codex`。


- [已完成] Step 73：补齐系统识别并替换真实 Logo
  - 用统一系统目录替代探测器与界面中的两份系统列表，补齐 OpenWrt、NetBSD、Slackware、Void、Pop!_OS、Zorin、EndeavourOS、Garuda、CachyOS、Azure Linux、elementary OS、Devuan、Artix、MX Linux；补充 openSUSE、麒麟服务器、CBL-Mariner 等别名。
  - 原有字母徽标替换为独立品牌 PNG，补齐通用 Linux、macOS 与 Windows Logo；共享 OsIcon 的主机列表、选择器、会话标签与状态栏同步生效，不新增设置或按钮。
  - ID_LIKE 按完整标识依次匹配，避免子串误判；已探测的系统不再被 RDP 协议强制覆盖成 Windows。图标本地打包，保留来源、摘要及许可证，可用生成脚本重建。
  - 验证：系统识别与别名、所有资源解码与尺寸、深浅主题和 RDP 图标优先级测试；生成图标总览进行视觉检查。

- [已完成] Step 73.1：调整 Windows Logo 留白
  - Windows 图标内容最大边长由 208px 缩小至 176px（约 15%），256px 画布与界面底板尺寸不变。生成脚本读取单图 `content_size` 配置，重新生成时保留该比例。
  - 更新图标总览，检查 20px 与 36px 显示效果。

- [已完成] Step 74：统一「连接之门」应用图标
  - 侧栏品牌替换为第二版透明图标，保持现有布局和中英文品牌展示。
  - 更新 macOS 全尺寸 AppIcon、Windows 多帧 ICO；增加 Linux hicolor 图标、窗口关联、中英文桌面入口与当前用户安装脚本。
  - 保留透明母版与统一导出脚本，`make icons` 可重建所有平台资源。
  - 验证：flutter analyze、现有 UI 快照测试、macOS Release 构建通过；检查 17 张透明 PNG 与 7 帧 ICO，Linux 安装脚本验证含空格路径及保留已有主题。Windows/Linux 尚未在对应系统构建验证。

- [已完成] Step 75：多平台测试文档与平台单元测试
  - 新增 docs/multi-platform-testing.md：平台差异总览、单元测试（P 编号）、端到端测试准备、手工测试清单（M 编号）、已发现的平台问题与验证记录；agents.md 增加多平台测试规定。
  - 新增 test/platform/ 单元测试 P-01 ~ P-06（Codex / dsh 平台实现、解压、PlatformUtils 与密钥权限、平台限定功能与 RDP 按键映射、原生窗口尺寸与构建脚本一致性），新增 `make test-platform`。
  - 验证：macOS 上 `make test-platform` 18 项通过，flutter analyze test/platform 无问题；Windows / Linux 待按文档验证。

- [已完成] Step 75.1：修复多平台测试文档中发现的平台问题
  - K-01：ssh_e2e_test 用户名兼容 Windows（USERNAME），Windows 上明确跳过，不再在加载时报错。
  - K-02：RDP 端到端测试按当前 ABI 定位原生构建目录（test/helpers/platform_tools.dart），Linux arm64 不再被跳过。
  - K-03：新增 lib/utils/file_permissions/ 接口（POSIX chmod、Windows icacls 只授权当前用户），PlatformUtils 收紧权限改为调用该接口。
  - K-04：Codex 安装器测试在 Windows 上用 .cmd 脚本模拟 codex，不再跳过。
  - K-05：Windows 原生库构建脚本支持 -Arch x86_64|arm64。
  - K-06（xdg-open）不处理。
  - 验证：macOS 上 test/platform、codex_installer、ssh / rdp / rdp_clipboard 端到端测试通过；Windows / Linux 待实机验证。

- [已完成] Step 75.2：Windows 自动化测试与构建修复
  - 修复 PowerShell 中文脚本编码、MSVC UTF-8 编译、原生命令错误码检查及 OpenSSL 库目录一致性。
  - 补齐 Windows 静态 zlib、MSVC 与 ccache 选择、RDP 头文件冲突及静态链接依赖；三平台统一剪贴板进度标志。
  - 修复日志句柄释放、同步测试 Dart 子进程定位、Windows 拖放测试坐标与 VNC 网络时序假设。
  - RDP 工具栏在窄窗口使用图标按钮并保留本地化提示，修复英文界面最小窗口溢出。
  - 扩展 P-06，新增 P-07；验证结果与未执行的实机项目记录在 `docs/multi-platform-testing.md`。
  - 验证：全量 123 项通过 / 18 项按条件跳过；最新平台专项与原生库加载、加密测试共 25 项通过；dsh 真实端到端 2 项、服务端测试 2 项通过；默认 `make` 生成含两个原生 DLL 的 Windows Release zip，`make server` 生成同步服务端。macOS / Linux 与手工远程联调待验证。

- [已完成] Step 76：Windows 安装程序与编译环境文档
  - Windows 默认打包目标生成中英文 Inno Setup 安装向导及便携包，当前用户安装、可选桌面入口、固定 AppId 升级并保留用户数据。
  - 分发前校验 Flutter / 原生库 / AOT 资源，附带应用本地 Visual C++ 运行库；增加 P-08 平台打包测试。
  - 新增 `docs/build-environment.md`，说明三平台工具链、Windows 开发者终端、依赖、打包产物与排障。
  - 验证：Windows 默认 `make` 生成 `dist/remlark-1.0.0-windows-x64-setup.exe` 与便携 zip；安装包 71 个条目完整性检查、中英文语言与运行库检查通过；`make test-platform` 26 项通过，新增测试静态检查无问题。安装 / 升级 / 卸载交互及 macOS / Linux 专项重跑待实机验证。

- [已完成] Step 77：Windows 无 Make 开发启动入口
  - 新增 `windows/run.ps1`，准备 Flutter 依赖、按需构建原生库并运行 Windows 应用；支持 `-RebuildNative` 与 `-PrepareOnly`，首次原生构建自动初始化 VS x64 环境。
  - README 与编译环境文档补充无需 Make 的运行命令；扩展 P-08 启动脚本验证。
  - 验证：从 PATH 移除 Make 后 `-PrepareOnly` 依赖准备通过（已有原生库），平台测试 28 项通过，新增测试静态检查无问题；图形启动及干净环境首次编译按 M-15 手工验证。

- [已完成] Step 78：简化 Agent 设置空列表
  - 无 Agent 时移除整块空状态卡片、图标和提示文字，内容区留空；删除中英文未使用的空状态文案。

- [已完成] Step 79：Linux 自动化验证、原生构建修复与安装包
  - 在 Ubuntu 26.04 x64 按多平台文档运行平台、客户端、服务端、SSH / RDP / dsh 端到端测试，记录真实执行与手工验证边界。
  - 统一 RDP 测试服务端的 OpenSSL 前缀，禁用不需要的 systemd；修复 Linux 测试字体路径与品牌文字宽字体溢出。
  - `make linux` 同时生成 Debian 安装包和便携 tar.gz，校验原生库与资源，按 ELF 计算系统运行依赖；新增 P-09。
  - 修复便携包路径含 `%` 时桌面入口无法加载；Linux 关闭 Android 间接依赖的可选 JNI，分发包无 Java 依赖。
  - 将实际工具链、依赖、构建命令、安装与卸载步骤写入 `docs/build-environment.md`。
  - 验证：全量 139 项通过 / 6 项跳过（4 项仅 macOS，2 项 dsh 另行执行）；最终平台 28 项、真实 dsh 2 项、服务端 2 项通过，静态检查无问题；deb / tar.gz / 同步服务端编译及本机解包启动验证通过；真实远程主机和干净机器安装流程仍待验证。

- [已完成] Step 80：GitHub Actions 多平台多 CPU 自动发布
  - 固定 Flutter 3.47.7；使用原生 Windows / Linux x64、arm64 runner，macOS 生成通用 zip / DMG。
  - Windows 安装器与 Makefile 参数支持 arm64，发布前检查全部附件与 SHA-256；增加 P-10。
  - CI 修复：隔离 FreeRDP 与应用标签、Windows 固定系统 tar、隔离 GNU Make / NMake 参数；Windows 使用独立 isolate 中的 Dart 流式解压。
  - 验证：GitHub Actions 第 8 轮五路构建与发布全部成功；Windows x64 / arm64 各 38 项平台测试通过，macOS 与 Linux 双架构各 33 项通过；v1.0.0 已发布 10 个安装 / 便携包及 SHA256SUMS。浏览器确认 Actions Success 与 Release 附件齐全，实机交互见 M-16。

- [已完成] Step 81：RDP H.264 硬件解码
  - 原因：原 RDP 只协商 RemoteFX / Progressive / Planar，解码全部在 CPU 上完成；高分辨率或视频画面时带宽与 CPU 占用高。
  - 构建：新增 FFmpeg 8.1.3 静态编译，仅包含 H.264 解码器、解析器与 swscale，关闭自动探测；按平台开启硬件加速：macOS VideoToolbox、Windows D3D11VA / DXVA2（MSVC 编译，configure 经 MSYS2 bash 运行，见 `build_ffmpeg_msvc.sh`）、Linux VAAPI。FreeRDP 开启 `WITH_VIDEO_FFMPEG` 与 `WITH_FFMPEG_HWACCEL`，关闭音频 FFmpeg；构建脚本记录 FreeRDP 特性标识，编译选项变化时自动重编旧缓存。
  - 胶水库：新增 `rmk_h264.c`，首次连接时探测 H.264 解码器与平台硬件设备（结果缓存），开启 GFX AVC420 / AVC444 / AVC444v2；硬件可用时 `SoftwareGdi=FALSE` 让 FreeRDP 为每个 H.264 表面启用硬件解码，否则保持 FFmpeg 软件解码；没有解码器时不协商 H.264。
  - 平台接口：`src/hwdec/rmk_hwdec.h` 定义设备类型 / 设备路径 / 环境准备，三个平台各自实现（macOS `videotoolbox`；Windows `d3d11va`，FreeRDP 默认 DXVA2；Linux `vaapi`，自动选择第一个可读写的 `/dev/dri/renderD*`），经 `FREERDP_HWCTX_TYPE` / `FREERDP_HWCTX_DEVICE` 传给 FreeRDP，用户已设置时保留。
  - Dart：新增 `rdp_h264.dart`（`RdpH264Support`），连接日志写明当前为 H.264 硬件解码或软件解码；画面合成与上传流程不变。
  - CI：macOS 安装 nasm；Linux 安装 nasm、libva-dev（deb 依赖由 dpkg-shlibdeps 自动加入 libva2 / libva-drm2）；Windows 安装 MSYS2 的 make、diffutils。
  - 测试：新增 P-11（三平台实现与构建选项、原生库探测）、M-17（真实 Windows 服务器 H.264 硬件解码）。
  - 验证：macOS x86_64 / arm64 编译通过；用 FreeRDP `avc420_decompress` 解码 libx264 编码的帧，VideoToolbox 硬解与软解输出一致；平台测试 37 项、RDP 端到端与剪贴板测试通过。Windows / Linux 的编译与硬解待在对应平台执行 `make test-platform` 与 M-17 验证。

- [已完成] Step 82：设置中开关 RDP 硬件解码
  - 设置页新增“远程桌面”分区（位于终端之后），提供“RDP 硬件解码”开关，默认开启，存储键 `rdp.hwdec`；修改后对新建的连接生效。
  - 说明文字显示本机能力：可用时显示设备名（VideoToolbox / Direct3D 11 (D3D11VA) / VA-API），显卡不支持时提示使用软件解码并禁用开关（保留已保存的选择），原生库缺失时提示组件未安装。
  - 原生库新增 `rmk_rdp_set_hwdec`（连接前调用），`rmk_h264_apply` 按设置决定 `SoftwareGdi`；关闭时仍协商 H.264，只是改用软件解码。取代 Step 81 中的环境变量开关。
  - 会话启动器把设置传给 `RdpSession.hardwareDecode`；连接日志写明“设置中已关闭硬件解码”。
  - 测试：新增 `rdp_hwdec_setting_test.dart`（默认值与持久化、日志描述、设置页开关状态与切换）；P-11 增加设置传递检查；`layout_overflow_test.dart` 自动覆盖新分区的中英文三种尺寸。
  - 验证：macOS x86_64 平台测试 37 项、设置测试 3 项、布局溢出测试通过。

- [已完成] Step 83：H.264 多平台解码测试与硬件实测探测
  - 原生库新增 `rmk_rdp_h264_self_test`：用与连接相同的 FreeRDP AVC420 流程把一帧 H.264 解码为 BGRA，供多平台测试调用；Dart 封装为 `RdpH264Support.selfTest`。
  - 探测改为实测：硬件设备可创建后，再用硬件实际解码内置帧（`rmk_h264_probe_frame.h`，左半 #E04020、右半 #3080C0）并校验颜色，成功才启用硬件。原因：虚拟机中的 VideoToolbox、异常的 VAAPI 驱动等能创建设备却无法解码，而 FreeRDP 的 FFmpeg 后端此时不会回退软件解码，会导致 H.264 画面失败。
  - P-11 增加实际解码测试（测试资源 `test/platform/fixtures/h264_320x240.h264`，BT.709 全范围，与 FreeRDP YUV 转换一致）：软件 / 硬件解码颜色正确且一致、无效数据返回失败；检查内置探测帧与测试资源字节一致。
  - Release CI 在原生库编译完成后再次运行 P-11，五个平台架构都实际解码，失败时不发布。
  - 验证：macOS x86_64 平台测试 41 项、设置测试、RDP 端到端与剪贴板测试通过；软件解码与 VideoToolbox 解码结果一致。

- [已完成] Step 83.1：Windows H.264 单元测试与构建兼容修复
  - 修复 FFmpeg MSVC 脚本在普通 PowerShell 中调用 `cygpath` 前未设置 MSYS2 工具路径、`CL=/FS` 被路径转换、中文编译器输出导致识别失败的问题；固定英文输出并提前检查 en-US 编译器资源。
  - 修复 MSVC 已生成 `.lib` 后仍尝试重命名不存在的 `libxxx.a` 的问题，改为检查三项 FFmpeg 静态库完整性。
  - 为 FreeRDP 3.32.2 的块末尾硬解错误标签补空语句，兼容 MSVC C11；补丁可重复执行。
  - P-11 增加构建环境、产物命名与 MSVC 标签兼容回归检查；同步更新多平台差异、K-20 ~ K-22 与 Windows 编译环境文档。
  - 修复 P-06 的 NMake 环境测试未指定 PowerShell 进程级执行策略的问题（K-23）；保持系统策略不变。
  - 验证范围为 Windows x64 原生编译、H.264 逐像素解码、硬件不可用时软件回退、设置与布局测试；用户暂无远程测试主机，M-17 不在本轮执行。
  - 验证：`make native-lib` 成功；`make test-platform` 46 项通过且无跳过，包含 P-11 的 8 项；硬解设置 3 项、中英文三尺寸布局 2 项、原生加密 1 项共 6 项通过；相关静态检查与补丁幂等检查通过。本机 D3D11VA 不可用，实际验证软件解码与硬件请求回退，真实 GPU 硬解及 ARM64 待实机验证；macOS / Linux 本轮未重跑。

- [已完成] Step 83.2：使用软件中保存的 Windows 主机进行真实 RDP 联调
  - 新增显式启用的 P-12（`test/platform/rdp_live_test.dart`），默认跳过，不访问用户配置与网络；启用时通过 ORM 的 protocol 索引读取指定 RDP 主机，禁止数据库写入与迁移，不记录凭据。
  - 实际检查硬解设置开启 / 关闭两种模式的认证、首帧、持续更新及可逆的开始菜单键盘操作；导出实际 BGRA 帧为 PNG，结束关闭菜单与连接。
  - 用 GDI TRACE 日志核对实际图形编码，区分本机具备 H.264 解码能力、服务器实际发送 H.264、本机实际使用 GPU 硬解三个不同结论。
  - 验证：AMD-Windows 的两种模式均实际认证成功，1280×800 画面分别收到 36 / 38 次更新，开始菜单打开 / 关闭与截图检查通过；平台测试 46 项通过 / P-12 默认跳过 1 项，显式启用 P-12 的真实测试 1 项通过，静态检查无问题。日志只观察到 ClearCodec / Progressive / Uncompressed，未观察到 H.264；本机 D3D11VA 不可用，真实 H.264 和 GPU 硬解仍待具备条件时验证。macOS / Linux 本轮未执行。

- [已完成] Step 83.3：Linux H.264 回归测试与 Release 编译
  - 环境：Ubuntu 26.04 LTS x86_64、Flutter 3.47.7 / Dart 3.13.5，基于 `e2a7417`；本机无 DRM 渲染节点，VAAPI GPU 硬解不可用。
  - 用发行版 NASM / libva-dev 包在 `build/` 中准备用户态构建依赖，重编 FFmpeg、FreeRDP 与 RDP / SSH 原生库；确认 H.264 解码器、VAAPI 硬件加速已编入，`ldd -r` 无缺失依赖或未解析符号。
  - `make test-platform` 41 项通过 / P-12 默认跳过 1 项；P-11 的 8 项全部执行，实际软件解码与请求硬解时的软件回退颜色正确且一致，无效码流不崩溃。
  - `make test` 客户端 156 项通过 / 7 项按条件跳过、服务端 2 项通过，覆盖 RDP 连接 / 输入更新 / 剪贴板、设置开关及中英文布局；修正解压模块和对应测试的两处花括号 lint，`make analyze` 全部通过。
  - 默认 `make` 成功生成 Linux Release、deb 与便携 tar.gz；两种分发包中的 RDP 库均与本轮原生构建一致，包内库实际解码颜色正确、软解与硬解回退最大 RGB 差为 0；deb 自动声明 libva2 / libva-drm2 依赖，APT 模拟安装通过。
  - deb 解包后在 Xvfb 中隔离数据目录启动两次，1280×820 窗口、960×640 最小尺寸和密钥持久化通过，截图检查正常。日志、截图和依赖环境脚本保留在 `build/validation/linux-h264*`。
  - 真实 VAAPI GPU 解码、真实远程 Windows 主机 M-17、Linux ARM64 本轮未验证；macOS / Windows 本轮未重跑。

- [已完成] Step 84：硬件加速版本 GitHub Actions 全矩阵构建验证
  - Release 工作流增加默认开启的仅构建模式，手工运行可使用分支代码，复用五路编译与打包流程并跳过发布。
  - 三个平台在原生库编译后重新执行 `make test-platform`，覆盖 H.264 实际解码和硬件不可用时的软件回退。
  - 修复 Windows CRLF 导致工作流配置回归检查误报；构建后设置 `RMK_REQUIRE_RDP_NATIVE=1`，原生库加载失败即阻止通过。
  - macOS ARM64 云端发现双色边界的软硬解色度转换差异；P-11 保持平坦区域逐像素差 ≤4，仅双色交界两侧各 2 像素允许 ≤64 的插值差，并记录差异列。
  - 验证：[Desktop Build #11](https://github.com/Remlark/Remlark/actions/runs/39615318096)，提交 `2aa69f3`，五路构建、安装包与构建后平台测试全部通过；macOS / Linux 双架构各 42 项、Windows 双架构各 47 项通过，各仅跳过需显式启用的真实主机测试 P-12。五组安装包已上传，发布任务按仅构建模式跳过。
  - macOS ARM64 VideoToolbox 实测：平坦区域差为 0，只有交界第 160 / 161 列差为 49；Windows / Linux runner 无硬解设备，实际验证软件解码与请求硬解时回退，RGB 差均为 0。真实 GPU 与远程主机仍按 M-17 手工验证。

- [已完成] Step 85：VERSION 统一管理编译与发布版本
  - 根目录 VERSION 保存 `1.0.0+1`；主应用与同步服务 pubspec 不再保存独立版本。
  - tools/utils/app_version.py 统一解析版本，三平台 Make 编译入口传入 Flutter 版本 / 构建号和 Dart 编译期版本；开发运行注入 Dart 版本，Windows 独立入口复用同一工具。
  - Linux deb、Windows 安装器、macOS DMG、Release 标签与附件清单统一读取 VERSION；macOS / Windows 拒绝元数据不匹配的旧应用。AI clientInfo 也使用统一版本。
  - 增加 P-13：解析与无效版本、CRLF / 中文路径、真实 Flutter 替身子进程的参数与退出码、发布标签、旧应用保护；更新 P-10 夹具为 VERSION。
  - 验证：[GitHub Actions](https://github.com/Remlark/Remlark/actions/runs/39622112845)，提交 `cb93ed1`，五路编译 / 打包全部通过；macOS / Linux 双架构构建前后各 48 项、Windows 双架构各 54 项平台测试通过，均只跳过需真实主机的 P-12。macOS / Windows 安装包元数据校验通过，发布任务跳过。
  - 本机：make test-platform 48 项通过 / P-12 跳过；Codex 7 项、同步服务端 2 项通过，静态检查通过；macOS Release 实际编译并核对 Info.plist 为 1.0.0 / 1。

- [已完成] Step 86：修复 macOS Dock 显示旧应用图标
  - 检查 Debug / Release AppIcon.icns，确认均已是“连接之门”；补充启动完成时显式从当前应用包加载图标并设置 NSApplication.applicationIconImage，不重启 Dock 或修改系统偏好。
  - macOS 图标逻辑独立在 Runner/Branding/ApplicationIcon.swift；Info.plist 显式指定 AppIcon。Windows 保持 exe 内嵌 ICO，Linux 保持应用 ID / desktop 关联。
  - 新增 P-14：三平台资源一致性 / 系统入口；macOS 编译真实原生图标实现，用隐藏测试进程验证实际图标刷新与缺失资源保留旧图标；新增 M-19。
  - 验证：本机 make test-platform 50 项通过 / P-12 跳过，静态检查、Debug / Release 编译、通用 zip / DMG 打包通过；macOS 原生读回图标与包资源一致，资源缺失时保留原图。
  - [GitHub Actions](https://github.com/Remlark/Remlark/actions/runs/39625870166)，提交 `5eacd93`，五路编译与打包全部通过；macOS / Linux 双架构构建前后各 50 项、Windows 双架构各 56 项平台测试通过，均只跳过 P-12。macOS 15 使用 512 像素、macOS 26 使用 1024 像素，P-14 按系统实际密度比较并只允许一档色彩舍入差。
  - 本地应用包目录时间已刷新，重新生成 dist/remlark-macos.zip 与 dist/remlark-1.0.0-macos-universal.dmg；真实 Dock 固定项的退出 / 重开与旧路径迁移仍按 M-19 手工确认。

- [已完成] Step 87：GitHub macOS 固定自签证书发布
  - 使用 MACOS_CERTIFICATE_BASE64 / MACOS_CERTIFICATE_PASSWORD 两个 Secrets；临时钥匙串导入与清理，配置错误立即失败。
  - 由内到外签 App，重新生成 zip / DMG 后签 DMG；保持 Release 权限，无公证。
  - 新增 P-15：三平台输入与失败保护、顺序检查；macOS 一次性证书真实签名、固定证书要求与清理。
  - 本机 macOS：make test-platform 52 项通过 / P-12 跳过；新增测试静态检查通过。P-15 使用一次性自签证书实际签 App，重复签名的证书要求一致，zip 解压后的严格签名验证与 DMG 签名验证通过，钥匙串搜索列表正确还原。

- Step 87.1：固定自签发布的云端与实机验证
  - 待推送后使用仓库 Secrets 执行五路仅构建 CI；Windows / Linux 仍需实际执行 make test-platform。
  - 用户实际证书导入、Intel / Apple Silicon 下载放行与升级权限按 M-20 验证。

- [已完成] Step 88：macOS 自签配置简化为证书和密码
  - 仅保留 MACOS_CERTIFICATE_BASE64 / MACOS_CERTIFICATE_PASSWORD；从导入证书自动识别唯一签名指纹，CI 随机生成临时钥匙串密码，旧两个配置不再读取。
  - 扩展 P-15：仅两项凭据导入、唯一身份选择、无身份与多身份拒绝；保留 macOS 真实自签 / zip / DMG 验证，Windows / Linux 不调用 Apple 工具。
  - 本机 make test-platform 52 项通过 / P-12 跳过，P-15 内部 9 项 Python 检查通过，含仅两项凭据的真实 App / zip / DMG 自签；Windows / Linux 的 make test-platform 与实际仓库证书仍待 CI 执行。

- [已完成] Step 89：跳板服务器分组搜索选择器（方案一）
  - 以独立对话框替代候选平铺菜单；左侧已有分组及数量，右侧搜索名称/端点与可滚动单选列表，底部确认后追加。
  - “未分组”为默认虚拟入口，可选服务器数量为 0 时隐藏，有候选时才显示；保留用户创建的空分组，补充分组为空及非空两种情况验证。
  - 保留当前主机/已选跳板排除及双协议 SSH 端点；切换筛选清除旧选择，取消无副作用，确认时校验候选有效性。
  - 复用主题和弹窗模板，增加可选副标题；新增中英文文案，支持深浅主题、长名称、空结果和固定操作栏。
  - 跳板选择器 5 项验证（含按需原生截图）、原有主机连接 3 项与全应用布局 2 项验证通过；覆盖 128 主机、60 分组、中英文、深浅主题、960×640 和 1440×900。

- [已完成] Step 90：共享代理服务器设置与主机选择（方案一）
  - 设置新增代理列表、名称/地址搜索、使用数量与操作菜单，新增/编辑使用统一弹窗；支持 HTTP / SOCKS5 和可选认证，中英文及深浅主题。
  - 主机编辑改为可搜索选择共享代理；可在当前表单内管理代理，取消主机不写入选择。
  - schema 3 添加代理表、主机引用及查询索引；旧数据在密钥初始化后按完整配置迁移去重，密码加密、同步时间不丢失。
  - 更新共享代理时事务刷新引用快照，新连接/重连使用新参数；使用中的代理禁止删除；导出/同步保留参数快照，导入自动恢复本地引用。
  - 代理 UI 4 项（含 macOS 原生组件截图）、全应用中英文布局 2 项，以及代理数据、数据库升级、现有主机/双协议、SSH/跳板/HTTP/SOCKS5 及同步回归 27 项通过；平台 P-16 纳入 make test-platform，macOS 53 项通过、真实 RDP P-12 跳过；Windows/Linux 尚待执行同一命令与 M-21。

- [已完成] Step 91：代理管理弹窗采用方案二，并增加可选连接测试
  - 管理弹窗改为 640px 内容自适应的双行列表；搜索/添加同一行，去掉表头和固定空白，长列表内部滚动、关闭按钮固定。
  - 添加/编辑代理提供可修改目标的连接测试，默认 example.com:443；显示进行中/成功/认证失败/超时，失败或进行中均可保存有效配置。修改参数、保存和关闭取消旧检测。
  - 以 ProxyConnectionTest 接口复用 HTTP CONNECT / SOCKS5 连接逻辑，增加整体超时、响应校验、取消和 IPv6 目标；公共目标解析放入 utils。
  - P-17 本地 Socket 测试 9 项、代理 UI 8 项（含两组快照）、既有 SSH 回归 12 项通过；macOS make test-platform 62 项通过 / P-12 跳过；Windows/Linux 同一命令与 M-22 仍待对应系统验证。

## 构建与运行命令

| 命令 | 说明 |
| --- | --- |
| `make` | 按当前平台打包 |
| `make mac` / `make linux` / `make windows` | 分平台打包（需在对应系统上执行，输出到 dist/；Windows 生成安装 exe 与便携 zip，Linux 生成 deb 与便携 tar.gz） |
| `make run` | 运行当前程序 |
| `make test` | 运行客户端与服务端测试 |
| `make test-platform` | 运行多平台单元测试（见 docs/multi-platform-testing.md，三个平台分别执行） |
| `make gen` | 重新生成 drift ORM 代码 |
| `make server` | 编译同步服务端（dist/remlark-sync-server/bundle/bin/server） |
| `make server-run TOKEN=xxx` | 本地运行同步服务端 |
| `make crypto-lib` | 编译 SSH 加密原生库（依赖 rdp-lib 的 OpenSSL；打包与 make run 会自动执行） |
| `make rdp-lib` | 编译 RDP 原生库（首次约 10 分钟；mac / linux / windows 打包会自动执行） |
| `make rdp-test-server` | 编译 RDP 端到端测试用的服务端 |

- [已完成] Step 92：GitHub 软件更新基础
  - 新增独立更新模块、“软件更新”设置分区、后台检查、侧栏提示、语义版本比较、GitHub 附件 SHA-256/大小校验、中英文与深浅主题；P-18 验证平台包映射。
  - 初版的应用内 Token 配置及手动安装流程已由 Step 93 替换，以 Step 93 和设计文档为准。

- [已完成] Step 93：复用本机 Git 凭据，点击升级后自动安装并重启
  - 移除 Token 输入和持久化，迁移删除旧配置；匿名失败时通过非交互 Git credential helper 读取本机 HTTPS 凭据，公开仓库不调用 Git。已在本机实际读取私有最新 Release v1.0.1，凭据不写入日志或文件。
  - “升级并重启”触发下载、校验、安装准备、助手握手、提交与有序退出；授权取消和准备失败保持当前应用运行。macOS zip/App 交换、Windows Inno 无人值守安装、Linux deb/便携分流及原用户重启。
  - P-19 实际隔离测试 POSIX 等待退出、未提交不安装、替换失败回滚、macOS 签名/版本与 App 交换、Git helper；Windows 同文件含本机安装助手/失败恢复测试。升级控制器另验证执行顺序及失败不退出。
  - 验证：静态检查无问题；更新业务/升级控制器/UI/全应用中英文布局共 21 项通过；macOS make test-platform 71 项通过，P-12 与 Windows 专属助手用例共跳过 3 项。三平台系统授权、真实安装重启按 M-23 验证；Windows/Linux make test-platform 尚待对应系统执行。

## 已知限制

- RDP 原生库已在 macOS x86_64 编译与连接测试通过、Windows x64 编译与 FFI 加载、Linux x64 编译与测试服务端端到端通过；真实 Windows 远程连接与 arm64 仍待实机验证。
- SSH 加密原生库已在 macOS x86_64、Windows x64 与 Linux x64 编译测试通过；arm64 仍待实机验证（库缺失时自动退回纯 Dart 加密）。
- RDP 支持 H.264（AVC420 / AVC444），经 FFmpeg 使用平台硬件解码（macOS VideoToolbox / Windows D3D11VA / Linux VAAPI），硬件不可用时软件解码；解码后的画面仍拷贝为 BGRA 再上传纹理，尚未零拷贝；暂不支持声音重定向。
- RDP 远程鼠标指针形状未同步，显示本地指针。
- RDP 远程复制的文件会立即下载到本地（上限 2GB），超过上限不传输并提示。
- 剪贴板测试使用自写的测试服务端，尚未与真实 Windows 服务器联调。
- VNC 剪贴板为 RFB 标准文本剪贴板（Latin-1，兼容 UTF-8 服务器）；VNC 协议没有文件传输标准，文件传输通过内置 SSH（兼容旧关联）经 SFTP 完成；增强剪贴板和 Finder/锁屏检测面向远程 macOS。
- AI 操作终端时命令是否结束由 Agent 根据输出判断；全屏程序（vim、top 等）与需要交互输入的命令由用户在终端处理。
- DeepSeek Harness 安装需要访问 nodejs.org 与 registry.npmjs.org（暂不支持镜像地址），依赖约占 1GB；Windows x64 与 Linux x64 真实安装与终端 JSON 协议端到端测试已通过。
- Codex 安装需要访问 GitHub（api.github.com 与 Release 下载地址，暂不支持镜像）；GitHub 未登录接口每小时限 60 次查询；OpenAI 兼容 API 不支持选择推理强度。
- 终端粘贴 / 拖拽上传无法自动获知 shell 当前目录，上传前会确认目标目录（默认 SFTP 最近浏览目录或用户主目录）。

- [已完成] Step 94：SSH 首次 TCP 不可达恢复
  - 根据 macOS 日志确认首次 TCP 建连 0–1ms 返回 errno 65、手动重连成功；底层系统原因仍需实机确认。
  - 在 utils 新增共用有限重试，分别封装 macOS/Linux/Windows 错误码策略；直连和代理 TCP 使用同一超时预算，最多四次，不重试 SSH 认证或代理握手。
  - 新增 P-20 三平台策略回归与 M-24 手工检查；定向回归（含本机 SSH 端到端）40 项通过；macOS `make test-platform` 90 项通过、3 项跳过，相关静态检查无问题。Windows/Linux 执行及真实问题复测待对应环境验证。

- [已完成] Step 95：修复数据库迁移重复添加代理列导致启动黑屏
  - 日志及只读检查确认 `user_version=2` 与已存在的 schema 3 结构不一致，启动抛出 `duplicate column name: proxy_uuid`。
  - 公共迁移工具按实际结构补齐列和索引，迁移 DDL 加事务保护；保留业务数据，兼容部分升级及重复打开。
  - 迁移/代理仓库回归 8 项通过；真实数据库隔离副本成功升级为 3，全部业务表数据摘要不变；macOS Debug 应用编译通过，原数据库未修改。

- [已完成] Step 96：统一添加主机与多协议连接配置
  - 新建主机取消协议下拉菜单，弹窗可任意组合 SSH、VNC、RDP，左侧切换各协议原有配置；一条主机记录保存多个连接入口。
  - 附加协议保存独立端口、账户和凭据；数据库中的附加密码和代理密码加密，无密码导出时清理附加协议凭据；保留旧版 VNC + SSH 兼容。
  - 卡片和列表分别用终端、显示器、窗口图标表示 SSH、VNC、RDP；菜单与工作区选择器按已启用协议提供入口。VNC 文件和增强剪贴板继续通过 SSH。

- [已完成] Step 97：主机系统图标与连接协议解耦
  - RDP 主机不再默认使用 Windows 图标；优先显示编辑时手动指定的系统，其次显示 SSH 自动探测结果。没有系统信息时仅从名称中的明确系统标识推断，仍未知时显示通用图标。
  - 主机编辑基本信息增加中英文系统图标选择器，覆盖 RDP 连接到 Ubuntu 等无法通过 RDP 自动探测系统的情况。
  - SSH 自动探测完成后刷新已打开的会话标签图标，无须关闭重开标签。

- [已完成] Step 98：多协议主机的服务器同步回归
  - 同一主机的 SSH、VNC、RDP 配置继续以单个 UUID、单份加密载荷同步；补齐附加 SSH 配置引用的密钥文件同步，并兼容旧版单密钥载荷。
  - 附加协议的主机指纹只保存在本机；拉取远端更新时，对相同协议端点保留本机指纹。
  - 双客户端端到端测试覆盖三协议配置、凭据、代理密码、附加 SSH 密钥、更新传播与本机指纹隔离。


- [已完成] Step 98：修复 RDP 重连时显示控制消息提前发送
  - 通过已授权 SSH 检查确认远端为 GNOME Remote Desktop 50.0，原用户桌面会话持续 active；重连日志明确报告在服务端能力发送前收到 monitor layout PDU，进而终止连接。
  - 三平台共用原生实现注册 DisplayControlCaps 回调，收到能力后再发送最新待调整尺寸；通道断开、重定向和释放均清理旧能力。
  - 新增 P-21，编译运行实际生产 C 函数验证协商时序与重建隔离，更新设计及 M-25 手工清单。macOS make test-platform 92 项通过、3 项跳过，定向静态检查通过；本机 RDP 连接/剪贴板回归 3 项通过，macOS 两架构原生库与 Debug 应用编译成功。真实桌面重连和 Windows/Linux 平台执行待验证。

  - Step 98 兼容性复核：对照微软 MS-RDPEDISP 消息顺序及 FreeRDP 3.32.2 标准客户端实现；扩展 P-21 验证能力先到及无能力服务端，不增加 Ubuntu 专用分支。Windows 服务端修复后重连/动态分辨率仍待实机验证。

- [已完成] Step 99：工作区紧凑主机卡片与全页新建会话（方案二）
  - 取消大幅引导和三台最近连接上限；按最近连接排序的自适应卡片网格支持滚动，首屏展示更多服务器。
  - 搜索全部主机的名称、地址、账户、分组；本页切换全部主机/最近连接，补充无主机、无历史和无搜索结果状态。
  - 新建会话改为同一工作区开始页，保留原标签、会话视图、网格和广播选择；支持返回原会话及独立协议入口。
  - 更新中英文、共用时间格式化、设计说明与回归验证；本次不新增平台分支或数据库操作。
  - 验证：工作区开始页、布局/广播、主机多协议入口、全应用中英文布局及时间格式化相关回归通过；静态检查无问题，macOS Debug 应用编译成功；截图对照记录见 design-qa.md，Windows/Linux 实机 UI 尚未验证。

- [已完成] Step 100：定位 macOS Dock 退出时的 SQLite 崩溃
  - 对照两份退出崩溃报告、应用日志和原生反汇编，确认 SQLite framework 在同一进程内加载两次，关闭时调用第二份库未初始化的互斥锁入口。
  - 独立 bundle id / 独立数据目录验证：正常退出连续 3 次成功；运行中替换同字节 framework 后稳定复现 SIGSEGV 和双重加载。
  - 记录开发包覆盖限制：完整构建前正常退出目标包，保留运行实例时使用独立副本；不针对构建覆盖问题改动业务退出顺序。证据位于 build/validation/dock-exit/。


- [已完成] Step 101：防止构建覆盖运行中的桌面应用
  - 增加统一进程检查接口及 macOS ps、Windows CIM、Linux procfs 独立实现，按实际输出路径识别运行实例，支持中文空格、大小写、自定义输出和独立副本。
  - 三平台 Makefile 打包/运行入口、版本包装工具、Windows 启动脚本、make clean 接入保护；检查失败或应用存活时拒绝覆盖，不自动退出或断开连接。
  - 新增 P-22（内部 12 项检查）及 M-26；macOS make test-platform 93 项通过、3 项跳过，静态检查通过；真实隔离 Debug 应用验证四个入口拒绝执行、framework 不变、原应用正常退出。Windows/Linux 实机执行尚待对应系统验证；直接 Flutter 命令不受仓库保护。


- [已完成] Step 102：复核单元测试是否改写运行中的应用包
  - 检查 Flutter 测试原生资产路径与本仓库可写 App 夹具，确认测试库写入 build/native_assets，签名/升级测试使用独立临时目录。
  - 保持隔离 Debug 应用运行时执行全平台测试集合及工作区/迁移/原生加密回归；286 个应用文件的 inode、时间、大小、SHA-256 均不变，运行副本只加载一份 SQLite，正常退出为 0。
  - 补充证据边界：覆盖已被复现为触发条件，历史崩溃报告不能单独确定写文件的具体进程；未发现本轮单元测试覆盖应用包。证据在 build/validation/test-app-isolation/。

- [已完成] Step 103：按主机快照重构服务器同步
  - `HostSyncBundle` 集中定义单个主机的版本化载荷：共享主机信息、SSH/VNC/RDP 全部连接方式、分组及引用的 SSH 密钥，以主机 UUID/更新时间作为唯一同步身份。
  - 下载先验证载荷与服务端索引一致，再在一个数据库事务中写入密钥、分组和主机；继续读取旧版单密钥载荷，未知新版本拒绝覆盖本机数据。
  - 设备本地指纹和最近连接时间不随载荷传输；仅在协议和端点未变化时保留本机指纹。单元及双客户端端到端测试覆盖版本兼容、身份校验、事务回滚和三协议配置往返。

- [已完成] Step 104：同步场景单元测试与竞态修复
  - 增加服务层内存接口夹具，测试真实加密与 ORM；覆盖七种协议组合、全部 49 种组合切换、整台版本冲突、凭据/密钥/分组、本机状态、故障恢复、事务回滚和并发编辑。
  - 修复上传冲突统计、下载缺失误报成功、索引与下载版本错配、并发调用提前返回、本机新编辑被覆盖和同版本误判一致；附加协议未记住的残留密码不进入载荷。
  - 服务端同版本不同密文拒绝覆盖，普通上传不能复活删除主机，显式恢复使用 `restoreDeleted`；批量下载去重并按 1000 台分批。更新测试矩阵 `docs/sync-testing.md`。
  - 验证：客户端同步及相关回归 139 项、服务端 10 项通过；客户端与服务端定向静态检查无问题。删除竞态保护涉及两端协议，客户端与同步服务端需配套更新。

- [已完成] Step 105：逐主机压缩加密、服务端全局串行与配置时间隔离
  - 保持每台主机 UUID 独立同步，单台主机快照先 gzip 再 AES-GCM 加密；新版 `v2:gzip:` 载荷兼容读取旧版未压缩密文。
  - 服务端对所有客户端、空间和主机共用 FIFO 队列，完整读取/比较/写入及删除均串行处理，失败不阻断后续任务。
  - 配置修改时间与最近连接时间独立：连接、系统探测、指纹和无实际变化的凭据回写不更新配置版本，实际修改用户名/密码才产生新版本。
  - 新增压缩兼容、配置时间隔离、队列顺序/并行数/失败恢复及双客户端并发回归。
  - 验证：客户端同步、配置时间和加密相关回归 167 项通过，服务端 17 项通过，两端定向静态检查无问题。旧载荷可读取；读取新版压缩载荷的客户端及启用串行队列的服务端需更新。

- [已完成] Step 106：同步配置、自动同步与服务端请求校验补测
  - 每轮同步在开始时固定服务器接口和派生密钥，途中保存新地址、令牌或口令不再混用两台服务器或两个口令；新配置从下一轮生效。
  - 同步结束只记录完成时间，不再重建自动同步定时器，避免退出（`stop()`）后被进行中的同步重新启动；配置写入串行化，始终落盘最新内存配置。
  - 客户端对路径中的主机 UUID 编码，服务端解码路由参数，导入的非标准 UUID 也能正常同步与删除；服务端对畸形 JSON、缺失或类型错误字段、空载荷返回 400 而非 500。
  - 新增配置加载/保存与密文落盘、自动同步周期/失败重试/退出、途中切换配置、重新加入遇到更新版本、未配置时移除、缺失密钥、各接口 401/500、批量上限、载荷超限、重复删除、特殊 UUID 端到端等回归。
  - 验证：客户端同步及相关回归 188 项、服务端 35 项通过；两端静态检查无新增问题。

- [已完成] Step 107：GitHub Actions 独立构建和发布同步服务端
  - 在现有 Release 工作流增加 macOS / Windows / Linux 各 x64、arm64 六路服务端构建，固定 Dart 3.13.5，锁定依赖、静态检查、单元测试后编译完整 bundle，无需 Flutter 和桌面原生库。
  - macOS 服务端使用 Intel / Apple Silicon 独立 runner 与独立发布文件名；桌面客户端保留 universal。主程序与 SQLite 动态库都校验原生平台/架构，完整归档 bin/lib 及资源，并在临时解压目录启动发布包验证真实数据库读写。
  - 发布任务等待桌面端和服务端全部成功，16 个附件统一生成 SHA256SUMS，服务端附件缺失同样阻止发布；新增 P-23 并扩展 P-10、M-13 及构建文档。
  - 验证：macOS `make test-platform` 95 项通过、3 项条件跳过，服务端 35 项通过；定向静态检查、工作流 YAML 解析及 `git diff --check` 通过。macOS x64 实际编译、归档、解包启动及 SQLite 写入/读取通过。Windows / Linux 与 macOS arm64 本轮尚未执行，需由更新后的 CI 及 M-13 实机验证；三平台 `make test-platform` 保留在桌面构建矩阵中执行。

- [已完成] Step 108：停止积累 Actions 压缩产物并清理历史文件
  - 仅构建模式不再上传桌面或服务端压缩包，取消额外的失败日志 artifact；正式发布仅临时中转，保留上限从 7 天降到 1 天。
  - 增加始终执行的清理任务：发布成功、失败及仅构建结束后，删除当前和本工作流历史已结束运行的 packages/logs，保护其他工作流、并行运行、Release 附件和原生缓存；分页先收集再删除，API 失败明确上报。
  - 经现有 Git credential helper 认证，核实历史运行均属于 release.yml 后实际删除 10 个远端压缩包，共 485,762,798 字节；API 复核 Actions artifacts 数量为 0。凭据未输出或写入仓库。
  - 新增 P-24 / M-27，扩展 P-10。macOS `make test-platform` 97 项通过、3 项条件跳过，定向静态检查、YAML 解析及 diff 检查通过；Windows / Linux 平台测试及新版 CI 自动清理仍待对应 runner 验证，三平台测试入口继续保留。

- [已完成] Step 109：修复 Windows 更新助手编码导致的平台测试失败
  - 工具层统一按显式 UTF-8 编码写入更新脚本；Windows 两个 PowerShell 助手携带 BOM，macOS/Linux 共用 shell 助手保持无 BOM 和完整 shebang。
  - 扩展 P-19：在所有平台检查 Windows x64/arm64 及 POSIX 输出编码，Windows 实际解析脚本；成功安装和失败回滚还检查安装器已执行与结果文件，防止语法错误被误判为回滚成功。
  - Windows x64 构建前后平台测试均为 102 项通过、6 项按条件跳过，修改文件静态检查无问题；Release 与安装器/便携包重新生成成功。macOS/Linux 本轮未实机执行，需在对应环境运行 `make test-platform`；Actions 原有三平台门禁保留，未跳过测试。

- [已完成] Step 110：Linux 全量回归与 1.0.2 Release 编译验证
  - 补齐客户端及服务端 13 处条件分支大括号，客户端与服务端 `make analyze` 均无问题，不改变业务行为。
  - 修复 P-22 的真实进程夹具：三平台统一复制 Python 并配置运行环境，macOS 保留临时签名；避免 Linux 多入口 coreutils 的 sleep 复制改名后无法启动。Linux 内部 12 项检查通过，平台集合 96 项通过、4 项条件跳过；macOS / Windows 修改后的夹具尚未实测。
  - 最终客户端全量测试显式启用原生库要求与真实 dsh 测试，426 项通过、11 项条件跳过；服务端 35 项全部通过。包括本地 SSH / SFTP、RDP 连接 / 剪贴板、AES-GCM、H.264 软件解码、同步场景及中英文布局。
  - `make native-lib rdp-test-server`、`make linux`、`make server` 成功，生成 1.0.2 Linux x64 deb、便携包及服务端归档。服务端解包启动和 SQLite 读写通过；便携包 9 个 ELF 文件依赖解析通过，Xvfb 下两次启动、窗口最小尺寸和密钥持久化 / 0600 权限通过。
  - 证据位于 `build/validation/current-*`。本轮仅验证 Linux x64；真实远端、VAAPI GPU、干净系统安装和其他平台仍需对应环境验证，详见多平台测试记录。

- [已完成] Step 111：同步配置保存后重新确认主机状态
  - 每次保存清除旧同步确认并刷新卡片及统计；删除服务器时保留同步选择、主机数据和配置版本，重新配置后可自动继续同步。
  - 完整配置保存后立即同步一次，包括关闭定时同步时；地址、令牌或口令变化清空旧同步时间，离线或部分失败的主机维持待同步。
  - 配置保存串行化，等待旧轮次完成再切换；单台上传增加配置代次校验，避免旧服务器响应恢复错误标记。增加专门回归并调整自动同步周期测试，更新同步设计及测试矩阵。
  - 验证：新增配置状态回归 9 项；同步服务、接口、主机快照、真实服务端端到端、配置版本及压缩加密相关回归共 179 项通过，定向静态检查与 `git diff --check` 通过。本次无平台分支或原生实现变更。

- [已完成] Step 112：独立同步协议 1.0 与兼容校验
  - 新增独立协议常量、请求/响应协议头和握手字段；所有数据请求先握手，服务端每个接口在业务前拒绝不支持的版本并返回 426。
  - 未声明版本的历史端固定按 1.0 兼容；未知或畸形版本拒绝，未来 2.0 不自动降级。补充中英文协议错误、客户端与服务端兼容/拒绝回归及真实服务联调。
  - 新增协议文档与未来多版本升级规则，明确与应用版本、主机快照及压缩加密封装版本分别维护。
  - 验证：客户端同步协议及相关回归 209 项、服务端全量 43 项通过；包含真实服务端联调，两端定向静态检查与 `git diff --check` 通过。本次无平台分支或原生实现变更。

- [已完成] Step 113：定位并修复 v1.0.3 Actions 平台门禁失败
  - 检查运行 40119649487：Windows x64/arm64 和 macOS 均失败于 P-22，Linux 两路及服务端六路通过，发布按门禁跳过。Windows 日志明确为默认代码页读取中文 Makefile 的 UnicodeDecodeError，测试改为显式 UTF-8。
  - macOS 日志为隔离进程存活但保护未抛错；本地复现 C locale 的 ps 转义中文路径导致同样漏检，查询子进程固定 UTF-8，保留调用方环境。复核三平台实现，Linux comm 显式 UTF-8，Windows 保留 UTF-8 JSON；macOS 夹具改用临时签名的系统 sleep 副本，避免依赖 CI Python 的进程路径。
  - 扩展 P-22 的查询环境透传、默认/C locale 真实进程及环境不被污染检查，更新设计及平台差异总览。
  - 验证：macOS `make test-platform` 99 项通过、3 项条件跳过；系统 Python 与 Homebrew Python 的 P-22 内部 12 项通过，关闭 Python UTF-8 模式并使用 C locale 后 12 项也通过，`git diff --check` 通过。修改后的 Windows/Linux `make test-platform` 尚需对应 runner 验证；未提交推送、未重跑远端 CI。

- [已完成] Step 114：替换 macOS ARM64 被终止的构建保护进程夹具
  - 复核运行 40123708220 / macOS job 120960531259，确认已检出 582e295；此次失败发生在启动后存活断言，复制并重签的系统 sleep 副本返回 -9（SIGKILL），尚未进入保护检查，与先前路径匹配失败不同。
  - macOS 改为用 xcrun clang 从专用 C 夹具生成当前主机架构的普通进程；Windows/Linux 保留 Python 副本。三平台均增加就绪标记与 10 秒限时等待，移除固定 0.2 秒启动假设；保留默认/C locale、运行时拒绝、退出后放行及进程清理验证。
  - 验证：本机 Intel macOS `make test-platform` 99 项通过、3 条件跳过；P-22 内部 12 项在默认环境与 C locale / Python UTF-8 关闭环境通过。C 夹具 x86_64/arm64 均编译成功，arm64 链接器生成的签名严格校验通过；`git diff --check` 通过。ARM64 实际执行及修改后的 Windows/Linux 平台集合仍需对应 runner 验证，未推送或触发远端 CI。

- [已完成] Step 115：新增 test* 标签触发的六路全量测试工作流
  - 新增独立 Full Platform Tests，支持 test 前缀标签与手动运行；macOS / Windows / Linux 各 x64/arm64 六路执行锁定依赖的客户端全套（含真实 dsh 安装及 ACP）、平台专项和服务端全套测试，失败后继续其他套件和平台。
  - 不执行产品构建、签名、打包、上传或发布。只恢复与 native 源码精确匹配的原生缓存，macOS ARM64 对应 Release universal 键；缺失时在 Summary 说明原生相关跳过范围。小型 C/Swift 夹具仍按测试需求生成。
  - 新增 P-25 四项回归、M-28 手工清单及平台差异总览，补充测试标签用法与覆盖边界；保留 v* 发布流程与构建后原生门禁。
  - 验证：本机 Intel macOS 最终启用原生库要求及真实 dsh 后，客户端全量 468 项通过、6 项按条件跳过；平台专项 103 项通过、3 项跳过，服务端全量 43 项通过。包含 P-22/P-25、真实本地 SSH/SFTP/RDP、原生 AES-GCM 与 H.264、同步及中英文布局；两端静态检查、新增测试定向分析、YAML/actionlint 与 diff 检查通过。日志在 `build/validation/pre-release-tests/`；未推送或触发远端测试，Windows/Linux 与 macOS ARM64 由新工作流实际验证。

- [已完成] Step 116：将 test* 工作流收敛为平台专项
  - 按最新范围改名 Platform Tests，保留三平台双架构六路与 test* / 手动触发，每路仅执行一次 `make test-platform`；删除客户端全量、真实 dsh、服务端测试及服务端依赖安装，移除本地 sshd 和无关字体依赖，超时上限降为 20 分钟。
  - 保留精确原生缓存及覆盖摘要、测试夹具工具链，不进行产品构建、上传或发布。P-25 更名为 `platform_test_workflow_test.dart`，明确禁止其他测试套件重新加入；同步更新设计、使用文档、平台差异及 M-28。
  - 验证：本机 `make test-platform` 103 项通过、3 条件跳过；定向静态检查、actionlint 和 diff 检查通过。仅验证本次涉及的平台集合，未重跑其他测试套件，未推送或触发远端 Actions。

- [已完成] Step 117：修复 Intel macOS 图标测试的栅格化舍入误报
  - 读取 test-1.0.3 运行 40126292484 的六路日志，只有 macOS x64 P-14 失败；P-22 与其他五路通过。日志显示实际图标表示为 512，使用相同源表示后最大 RGBA 通道差值为 2，超出原测试阈值 1。
  - 只调整 Swift 测试夹具为最多两个色阶，仍比较全部通道；补充接受 2 / 拒绝 3、空数据和不同长度边界，错误图标必须超过容差，缺失资源后保留像素完全相等检查。不修改生产刷新代码或三平台图标资源。
  - 更新 P-14 与平台差异、设计说明。macOS `make test-platform` 103 项通过、3 条件跳过，diff 检查通过；没有重跑其他套件或触发远端 Actions，Intel macOS 15 runner 仍需包含本次修复的新测试标签验证。

- [已完成] Step 118：移除图标专项自动化测试
  - 按用户要求删除图标资源/系统关联测试及 macOS Swift 图标读回夹具，平台专项与全量测试均不再收集图标用例。
  - 设计和平台差异移除自动化比较要求，P-14 标记已移除、保留编号；图标外观及系统入口沿用 M-12、M-19 手工检查，历史验证记录保留供追溯。
  - 验证：macOS `make test-platform` 101 项通过、3 条件跳过，未发现已删除夹具的代码引用，diff 检查通过。未执行其他套件或触发远端 Actions。

- [已完成] Step 119：修复 Windows ARM64 原生源码下载缺少校验
  - 定位 Release 40127434522 / job 120971764135：Windows ARM64 平台专项及服务端构建通过，OpenSSL 编译安装完成后，zlib 1.3.1 下载内容被系统 tar 报 Unrecognized archive format；原日志未保存文件，无法进一步确定错误响应来源。
  - 三平台共享 Python 标准库下载工具，每来源最多三次尝试、完整 gzip CRC/tar 根目录校验、同目录临时文件及原子替换。Windows zlib 使用官方 GitHub 优先、官网备用和固定 SHA-256；所有尚需编译的源码提前下载，避免 OpenSSL 编译后才暴露下载错误。
  - 新增 P-26 两项平台回归，包含九项 Python 网络替身/真实归档/CLI 检查，覆盖错误页、HTTP/传输失败、截断、CRC/目录/哈希异常、镜像回退和临时文件清理；更新平台差异及 M-29。
  - 验证：macOS `make test-platform` 103 项通过、3 条件跳过；定向分析、POSIX 语法及 diff 检查通过。两个 zlib 官方来源实际下载的 SHA-256 一致，新工具真实下载并校验通过，Windows 脚本 BOM 保留。未执行产品构建或其他测试套件，未推送/触发 Actions；Windows x64/arm64 及 Linux 的实际构建与平台执行仍需对应 runner 验证。

- [已完成] Step 120：本地审查原生构建失败恢复与额度浪费点
  - 补齐下载退避/永久错误回退/慢速预算、本地磁盘错误不重试、已验证包复用及非 UTF-8 日志兼容。源码暂存解压、关键文件/完成记录校验后原子发布，失败恢复旧目录，不能再按“目录存在”跳过半成品。
  - Windows 在下载和编译前检查工具、cl 实际目标宏、MSYS2 和英文资源；POSIX 前置检查架构/系统依赖，Linux arm64 统一 aarch64。OpenSSL 用 finally 恢复目录；阶段重建清除旧输出和失效 CMake 目录，不屏蔽清理失败。
  - 新增跨平台完成记录工具：所有必需库/头文件、摘要、配方、安装位置和目标目录都一致才可复用；安装成功后提交记录，单个非空库不能代表完成。新增阶段缓存，普通失败保留完成依赖/验证包，胶水 C 改动不作废第三方进度；完整库缓存要求所有依赖和双原生库齐全、通用包两架构完成。
  - 统一发布/专项的缓存路径集合，排除大型临时编译目录；缓存环境身份绑定工作区、校验器及 MSVC，避免不可更新的旧缓存反复命中。P-26 扩展至 19 项 Python 回归，新增 P-27 的 15 项阶段/前置检查回归和 PowerShell 包装器检查，更新 M-29/M-30。
  - 验证：本机平台集合 106 项通过、3 条件跳过；Python 3.9.6 与当前 Python、ASCII 严格控制台回归通过。本地 PowerShell 7.6.8 解析全部脚本并以默认/Legacy 参数模式执行实际包装器、真实 Fetch 和缺工具驱动分支；OpenSSL/FreeRDP/FFmpeg 三个上游源码实际下载校验与暂存解压通过。定向分析、bash 语法、actionlint 和 diff 检查通过。全程未编译产品、未运行客户端全量/服务端/dsh、未推送或触发 Actions；Windows PowerShell 5.1 + MSVC 与完整三平台构建/缓存服务恢复未实际执行，不能等同于完整 Windows 构建通过。

- [已完成] Step 121：发布失败保留中转包并为 CI 网络安装加重试
  - cleanup 改为 `needs.publish.result == 'success'` 时运行，只删除当前运行的 packages/logs；任一平台失败都不删，已成功平台的包留给 Re-run failed jobs。不再自动清理历史运行，避免误删失败待重跑的包。
  - 中转包保留期 1 天改为 7 天，upload-artifact 开启 overwrite，重跑同名包可以覆盖。
  - 新增三平台共用的 `tools/utils/retry_command.py`（默认 3 次、指数退避、重试前清理半成品、命令不存在不重试、返回最后退出码）。release.yml 与 test.yml 的 Flutter 克隆/初始化、apt-get、brew、choco、MSYS2 pacman、pub get 以及 gh release upload/edit 都经过它。
  - P-24 改为验证仅当前运行和成功后清理；新增 P-28 及 M-31，M-27 增加失败重跑验收。本机 macOS `make test-platform` 108 项通过、3 条件跳过；Windows/Linux 需在测试仓库 Actions 验证。

- [已完成] Step 122：修复 Windows 中文路径解压与 PowerShell 5.1 测试哈希
  - 测试仓库 Release 40136798355 两路 Windows 在平台测试阶段失败：System32 bsdtar 把中文路径参数转成 `??` 后打不开压缩包；PowerShell 5.1 从 pwsh 7 启动时 `Get-FileHash` 无法加载。
  - `source_archive.py` 解压时把工作目录设为压缩包目录，只传 ASCII 相对文件名，三平台共用；`windows_build_checks.ps1` 改用 python 计算哈希。P-26 新增 tar 参数回归。
  - 重跑后 P-27 在 Dart 默认 30 秒处超时，且看不到输出。启动 5.1 时把 PSModulePath 重置为 5.1 默认模块目录（根除 pwsh 7 模块干扰）；改为流式收集输出，进程限时 4 分钟、超时先杀进程再打印已有输出；脚本各阶段输出 `==>` 标记。
  - 验证：macOS `make test-platform` 108 项通过、3 条件跳过；Windows x64/arm64 待测试仓库重新运行。

- [已完成] Step 123：审查并放宽慢速 runner 上的短时限
  - Windows ARM64 上 P-27 超出默认 30 秒，x64 通过。所有启动外部进程的平台测试统一设置 3 分钟文件级时限；新增 `test/utils/windows_powershell.dart`，测试中启动 PowerShell 5.1 时统一重置 PSModulePath。
  - 构建保护的 Windows CIM 查询同样重置 PSModulePath，查询上限 10 秒改为 60 秒；源码解压上限 120 秒改为 600 秒；代理回环与 POSIX 更新助手测试的秒级等待放宽。
  - 在多平台测试文档的维护规则中写明时限和 PowerShell 环境要求。本机 macOS `make test-platform` 108 项通过、3 条件跳过；Windows 待测试仓库验证。


- [已完成] Step 124：VNC / RDP 连接失败自动重试
  - VNC TCP 入口复用 SSH 的跨平台不可达策略与 15s 总预算；RDP 按 FreeRDP 网络错误码有限重试，60s 总预算，每次重建客户端并重新解析代理。统一等待 500ms、1s、2s，最多四次，不自动重复认证或证书确认。
  - 共用重试工具支持原生错误分类和取消；关闭/替换连接会使旧操作失效，VNC 取消后台建连并优先关闭 socket，RDP 释放原生客户端并隔离旧回调。保留现有连接中/失败界面与手动重连入口，超时提示支持中英文。
  - 新增平台 P-29，覆盖三平台 TCP 策略、真实 VNC TCP 入口、RDP 自动恢复/重试上限/认证和证书/关闭与旧回调；真实交互登记 M-32。本机 macOS make test-platform 125 项通过、3 条件跳过，VNC/RDP 本地回归 15 项通过，相关静态检查通过；Windows/Linux 的 make test-platform 待对应系统执行。

- [已完成] Step 125：Shell 字重重置兼容与颜色继承回归检查
  - 修复 xterm 4.x 的 SGR 22 仅清除淡化、粗体继续继承的问题，在终端兼容层同时清除粗体，保留其他独立属性。
  - 新增终端模型回归：完整样式重置的全部分包边界、独立前景/背景重置、字重重置和正常跨行状态保留。颜色重置未复现异常，截图中的持续变色仍需触发命令或原始输出确认，不能据此认定已解决。

- [已完成] Step 126：扩展 Shell 各类格式防残留测试
  - 新增 24 项模型矩阵测试：8 种属性及全部 256 种组合、前景/背景的 16 色与全部 256 色、RGB 边界及混合值、单项关闭、完整重置、复合指令顺序、历史文字保护、中文日志/提示符的逐字符及随机分包、保存恢复光标和会话隔离。
  - 新增 2 项真实绘制器像素测试，分别覆盖深色和浅色主题，验证彩色及格式化字符缓存不会污染重置后的相同字符。
  - 本机 macOS 执行新增与既有样式、reflow、终端面板测试共 33 项全部通过；相关 Dart 静态分析通过。本步只扩展共用 Dart 测试，无平台实现改动。对远端未发出重置的输出仍按终端协议保留格式，不将该场景误报为已解决。

- [已完成] Step 127：复现日志筛选丢失跨行颜色重置
  - 根据补充截图核对相关项目本地 GORM v1.25.12 依赖源码，确认错误日志重置在第二行；用构造的同结构日志及实际 grep 验证只保留错误行时重置丢失，与截图中紫色粗体扩散、SQL 行后暂时恢复一致。未采集远端原始日志，不将推断冒充原始数据验证。
  - 新增 3 项回归：完整两行日志提示符正常、筛掉 SQL 行后复现紫色粗体、末尾补发重置在所有分包位置恢复正常；保持终端协议行为，不引入逐行自动重置。

- [已完成] Step 128：终端手动恢复文字格式
  - 按用户选择，在右键菜单与工具栏同时增加“重置文字格式”；工具栏采用清除格式图标，提供说明及无障碍名称，文案支持中英文。
  - 会话层统一直接清除本地当前样式，保留历史和光标、不发送远端命令，也不向解析器插入控制序列；无需重新连接即可恢复后续输出。
  - 扩展终端界面测试覆盖两个入口、完整属性恢复、历史/光标保留、不发送输入，以及残缺 CSI 接收期间恢复后继续解析。本次为共用 Dart UI/模型改动，无按平台分支或原生接口变化。
  - 验证：35 项样式/日志/reflow 测试通过；界面测试在补齐剪贴板平台通道替身后通过，实际模拟鼠标右键并点击菜单项、点击工具栏按钮验证恢复行为。相关静态分析与 diff 检查通过。

- [已完成] Step 129：提升终端格式恢复按钮的可读性
  - 工具栏由纯图标改为“恢复默认”回转箭头图标 + “重置文字格式”文字，沿用中英文翻译和悬停说明；右键菜单同步图标，不改变恢复行为。
  - 更新界面测试的菜单定位，避免新增按钮文字与菜单项重名；终端界面回归与相关静态分析通过。


- [已完成] Step 130：统一应用名称为大写 R 的 Remlark
  - 修正 macOS PRODUCT_NAME、App/可执行文件/Xcode 测试宿主；Windows 产品属性/可执行文件/安装器快捷方式；Linux 主程序/桌面入口/便携安装脚本及系统命令入口。
  - 同步桌面与服务端分发包名、Makefile、签名公证、发布清单、自动更新映射及测试夹具；导出 JSON 与新密钥默认名称使用 Remlark 前缀。构建保护识别新旧大小写的运行进程。
  - 保留 Dart/npm 包名、应用 ID、Debian 包名、已有数据路径、FFI/MethodChannel/协议标识。旧版本按小写名称查找更新，名称切换需要手动下载安装本次新版，不修改当前已安装或运行中的程序。
  - 新增 P-30 三平台名称一致性回归与 M-33 安装检查；macOS make test-platform 128 项通过、3 条件跳过，相关 Dart 静态检查及 diff 检查通过。Windows/Linux 无当前实机环境，待对应系统执行 make test-platform 与安装验证；未构建、发布或替换本机应用。

- [已完成] Step 131：修复单页增删会话后恢复网格遗漏新会话
  - 复现网格 → 单窗口 → 关闭一个会话 → 新开一个会话 → 网格时仅显示剩余旧会话的问题；新增两项回归在修复前均失败。
  - 单窗口期间继续维护已保存的网格，新会话按顺序补入空位，保留用户排除的旧会话、9 格上限与 SFTP 排除规则；广播和临时聚焦行为沿用原规则。
  - 网格状态、工作区开始页及中英文布局回归共 7 项通过，覆盖复现步骤、远程桌面、容量限制和广播隔离；相关 Dart 静态分析与 diff 检查通过。共用 Dart 逻辑，无新增平台分支或本地化文案。

- [已完成] Step 132：系统补齐工作区状态切换测试并修复关联问题
  - 新增 24 项三协议/四模式/活动与非活动关闭组合、26 项 0～12 会话容量边界，以及广播结束、SFTP 父子关闭、开始页、标签排序、无效选择等专项测试；4 个固定种子各运行 400 步，逐步检查会话选择与可见焦点。
  - 首轮扩展用例中 8 项失败，暴露广播结束后聚焦与活动标签不一致、直接激活入口绕过网格/广播规则等问题；统一激活逻辑与广播退出后的聚焦恢复，并补齐标签排序必定刷新通知。
  - 新增中英文真实布局菜单测试，检查关闭/新开后两列画布坐标、聚焦按钮及返回网格，并验证 VNC 视图 State 没有重建。复用测试工具放入 test/utils。
  - 本次只修改共用 Dart 状态与标签排序回调，无新增平台分支或界面文案；测试使用未连接会话，真实远程连接和三平台实机交互不计入验证结论。
  - 验证：工作区布局、状态矩阵、中英文菜单、开始页及全应用布局回归共 73 项全部通过（含 1,600 步连续操作）；相关 Dart 静态分析和 diff 检查通过。

- [已完成] Step 133：修复硬件解码不支持服务端 H.264 视频流时 RDP 白屏
  - 现象：Intel iMac 用 Remlark 连接 Mac mini 上的 ProRDP 服务白屏，Windows App 正常。连接成功、首帧尺寸正确，但 VideoToolbox 无法为服务端的 High 档次 Level 5.0 1080p 码流创建会话（内置 320×240 探测帧可正常硬解），FreeRDP 3.32.2 的 get_format 在硬件初始化失败后不回退软件格式，所有 AVC420 更新被丢弃。
  - 修复：rmk_h264.c 在 GFX 通道建立后包装 SurfaceCommand，每个表面首个 H.264 命令到达、FreeRDP 尚未创建解码器时，用该命令的实际码流和更新区域试解码；硬件失败而软件成功则打开 SoftwareGdi，该表面及后续表面改用软件解码，同尺寸表面校验通过后不重复校验。软件也失败视为数据问题，不改变解码方式。
  - 新增 RMK_EV_H264_SOFTWARE 事件，Dart 记录警告日志，界面不变；新增 rmk_rdp_h264_stream_check 接口供测试。三平台共用同一胶水代码，D3D11VA / VAAPI 拒绝码流时同样回退。
  - 验证：用应用保存的配置真实连接 ProRDP，修复前硬解路径整帧白色、软解正常；修复后开启硬解时自动回退，画面与软解一致；重新运行应用后实际连接 ProRDP 显示正常（用户确认）。P-11 新增 2 项通过，macOS make test-platform 130 项通过、3 项条件跳过；x86_64 / arm64 原生库编译通过，Dart 静态检查通过。Windows / Linux 待在对应系统执行 make test-platform。

- [已完成] Step 134：修复 Windows CRLF 检出导致的平台测试误报
  - Windows x64 上 P-30 Linux 桌面入口检查与 P-11 H.264 回退源码检查失败，原因是断言片段含换行而 Windows 检出为 CRLF；产品代码无问题。
  - 新增 test/utils/source_text.dart 的 readSourceText 统一 LF，两项测试改用它；multi-platform-testing.md 维护规则补充含换行断言的要求。
  - 验证：本机将相关源文件转为 CRLF，修复前复现 2 项失败、修复后通过；macOS make test-platform 130 项通过、3 项条件跳过。Windows / Linux 待 CI 重新执行。

- [已完成] Step 135：定位 Windows ARM64 构建保护未检出真实进程（随 Step 136 放弃 ARM64 关闭）
  - 现象：Windows ARM64 CI 中 P-22 真实进程测试未检出测试启动的 Remlark.exe（查询成功但无匹配），x64 / macOS 通过；1.0.3 时该测试在 ARM64 通过，此后 Windows 侧仅有大小写与查询超时 / PSModulePath 调整。
  - 已完成：测试未检出时输出 Python 架构、目标与 build 目录解析结果及查询原始行（ascii 转义）。本机 build_guard_test.py 12 项通过，诊断输出格式已在 macOS 验证。
  - 结论：没有 Windows ARM 测试机，Step 136 放弃 Windows ARM64 桌面端，不再追查原因；诊断输出保留。

- [已完成] Step 136：放弃 Windows ARM64 桌面端
  - 原因：没有 Windows ARM 测试机，无法实机验证；Windows 11 ARM 设备可仿真运行 x64 版。仓库私有、无存量 ARM 用户，不做旧版自动升级兼容；服务端 Windows ARM64 保留。
  - CI：release.yml 桌面矩阵去掉 windows-11-arm（服务端六路不变），`make windows` 不再传架构；test.yml 平台专项改为五路；prepare.py 必需附件由 16 个改为 14 个。
  - 打包与更新：build.ps1 只接受 x64 并固定附带 vcruntime140_1.dll，remlark.iss 去掉 arm64 分支（保留 x64compatible）；Makefile 移除 WINDOWS_ARCH，ARM64 主机在 guard-windows 直接停止；更新器 Abi.windowsArm64 不再映射安装包。原生库脚本 arm64 参数与 Codex/dsh 的 arm64 映射保留，仅供 ARM 主机本地开发。
  - 测试：P-10、P-25、P-18、P-19、windows_packaging 同步更新。本机 Intel macOS make test-platform 130 项通过、3 项条件跳过；make -n 模拟 ARM64 主机确认 guard-windows 停止。Windows x64 / Linux 待 CI 执行。
  - 补充修复：windows_packaging_test.dart 中 3 项仅在 Windows 运行的打包测试仍以 `-Arch arm64` 调用 build.ps1，首次提交时 macOS 本机跳过未发现，Windows x64 CI 失败。改为：暂存测试用 x64；新增「x64 必须包含 FH4 运行库，ARM64 参数被拒绝」；VS 2026 CRT 查找夹具改到 redist/x64 并放齐三个 dll。已复查全部 build.ps1 调用与 arm64 参数，其余为 Linux / 服务端 / 原生库脚本保留项。本机无 PowerShell，这 3 项待 Windows CI 验证。
  - Release 的 macOS 依赖安装增加 pkgconf：托管 macos-15 预装 pkg-config，自托管 Mac mini 缺失导致 rdp-lib 失败；已安装时 brew 跳过。
