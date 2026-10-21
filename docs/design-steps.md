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

## 已知限制

- RDP 原生库已在 macOS x86_64 编译与连接测试通过、Windows x64 编译与 FFI 加载、Linux x64 编译与测试服务端端到端通过；真实 Windows 远程连接与 arm64 仍待实机验证。
- SSH 加密原生库已在 macOS x86_64、Windows x64 与 Linux x64 编译测试通过；arm64 仍待实机验证（库缺失时自动退回纯 Dart 加密）。
- RDP 暂未启用 H.264（AVC）编码，使用 RemoteFX / Progressive / Planar 等编码；暂不支持声音重定向。
- RDP 远程鼠标指针形状未同步，显示本地指针。
- RDP 远程复制的文件会立即下载到本地（上限 2GB），超过上限不传输并提示。
- 剪贴板测试使用自写的测试服务端，尚未与真实 Windows 服务器联调。
- VNC 剪贴板为 RFB 标准文本剪贴板（Latin-1，兼容 UTF-8 服务器）；VNC 协议没有文件传输标准，文件传输通过内置 SSH（兼容旧关联）经 SFTP 完成；增强剪贴板和 Finder/锁屏检测面向远程 macOS。
- AI 操作终端时命令是否结束由 Agent 根据输出判断；全屏程序（vim、top 等）与需要交互输入的命令由用户在终端处理。
- DeepSeek Harness 安装需要访问 nodejs.org 与 registry.npmjs.org（暂不支持镜像地址），依赖约占 1GB；Windows x64 与 Linux x64 真实安装与终端 JSON 协议端到端测试已通过。
- Codex 安装需要访问 GitHub（api.github.com 与 Release 下载地址，暂不支持镜像）；GitHub 未登录接口每小时限 60 次查询；OpenAI 兼容 API 不支持选择推理强度。
- 终端粘贴 / 拖拽上传无法自动获知 shell 当前目录，上传前会确认目标目录（默认 SFTP 最近浏览目录或用户主目录）。
