# 主机同步测试

测试以单个主机快照为单位，使用确定的版本号模拟两端数据；服务层单元测试使用内存接口和独立内存数据库，序列化、加密、仓库与事务均使用生产实现。端到端测试另启动真实同步服务，验证客户端与服务端协议一致。

## 覆盖范围

| 场景 | 验证内容 | 测试文件 |
| --- | --- | --- |
| 同步方向 | 两端为空、本地新增、远端新增、仅本地主机、本地/远端较新、重复同步、同 UUID 重新关联 | `test/sync_service_test.dart` |
| 多协议 | SSH/VNC/RDP 七种非空组合完整恢复；全部 49 种协议组合切换；新增/移除协议、主协议切换不遗留入口或混用指纹 | `test/sync_service_test.dart`、`test/host_sync_bundle_test.dart` |
| 整台冲突 | 不同设备分别修改不同协议时，按整台主机版本取舍；同时间戳待同步记录读取服务器已提交版本；本机保存版本严格递增 | `test/sync_service_test.dart`、`test/host_sync_bundle_test.dart` |
| 凭据与依赖 | 各协议端口/账户/密码独立，RDP 域配置、代理密码、SSH 密钥恢复；密钥去重及旧 VNC 内置 SSH；未记住的密码不传输，取消记住密码清除本机旧值 | `test/sync_service_test.dart`、`test/host_sync_bundle_test.dart`、`test/sync_e2e_test.dart` |
| 删除与恢复 | 远端删除解除同步并保留本机配置；空删除标记不创建占位主机；删除失败可重试；显式重新加入恢复；上传/下载期间远端删除均不被旧配置复活 | `test/sync_service_test.dart`、`server/test/sync_repository_test.dart` |
| 网络与重试 | 未配置、离线、401、503、超时、下载缺失、部分主机失败后重试；失败不记录整轮成功时间，状态可恢复 | `test/sync_service_test.dart`、`test/sync_api_test.dart` |
| 并发 | 索引后远端再次修改、上传时产生版本冲突、本机等待上传/下载期间继续编辑、同时手动/定时触发共享真实同步结果 | `test/sync_service_test.dart` |
| 数据完整性 | 口令错误、密文篡改、损坏 JSON、UUID/时间戳错配、非法或未来版本、未知协议、损坏密钥列表均拒绝覆盖 | `test/sync_service_test.dart`、`test/host_sync_bundle_test.dart`、`test/sync_api_test.dart` |
| 本机状态 | 指纹不传输；端点不变时按协议保留指纹；地址或端口变化清除旧指纹；最近连接时间保留本机值 | `test/host_sync_bundle_test.dart`、`test/sync_e2e_test.dart` |
| 原子恢复 | 主机写入失败时新增密钥、分组和主机一起回滚；其他主机已完成的同步可以保留并在重试时跳过 | `test/sync_service_test.dart`、`test/host_sync_bundle_test.dart` |
| HTTP 与服务端 | 认证头、路径、删除状态与密文版本同时读取、1001 台分批；同版本同密文幂等、不同密文冲突；不同令牌空间隔离 | `test/sync_api_test.dart`、`server/test/sync_api_test.dart`、`server/test/sync_repository_test.dart` |
| 压缩与加密 | JSON 先 gzip 后 AES-GCM；中文往返、压缩体积、密文篡改、错误口令、无效 gzip、旧版未压缩密文兼容 | `test/sync_compression_test.dart`、`test/sync_e2e_test.dart` |
| 配置修改时间 | 七种协议组合下连接、系统探测和指纹均不改变配置时间；重复用户名/密码回写不产生版本；实际修改凭据才待同步；连接多次不产生额外上传 | `test/host_configuration_version_test.dart`、`test/sync_service_test.dart` |
| 全局串行处理 | FIFO 顺序、100 个任务最大并行数为一、失败不阻断队列；多客户端同主机/跨主机/跨空间并发仍保留正确版本；真实双客户端同时同步 | `server/test/serial_executor_test.dart`、`server/test/sync_repository_test.dart`、`test/sync_e2e_test.dart` |

## 执行

仓库根目录执行同步单元测试与真实服务回归：

```sh
flutter test --no-pub test/sync_compression_test.dart test/host_configuration_version_test.dart test/sync_service_test.dart test/sync_api_test.dart test/host_sync_bundle_test.dart test/sync_e2e_test.dart test/host_connection_forms_test.dart test/vnc_ssh_config_test.dart test/core_test.dart
```

在 `server/` 目录执行服务端测试：

```sh
dart test
```

这些测试不会连接用户配置的同步服务器，也不会使用真实主机凭据。内存数据库、临时服务和临时数据库文件在测试结束时释放。

## 冲突和兼容规则

- 不同版本以较新的整台主机为准；不逐字段合并来自不同版本的 SSH、VNC、RDP 配置。
- 同版本的待同步主机先读取服务器已提交内容，不能仅凭时间戳相同就标记为已同步。服务器拒绝用不同密文覆盖同一个已提交版本。
- 普通上传携带 `restoreDeleted: false`，遇到删除标记返回冲突；只有用户显式“重新加入同步”携带 `true` 才能恢复。删除竞态保护需要更新后的客户端和服务端配合，旧客户端恢复已删除主机前需要升级。
- 下载使用批量响应与密文一起返回的版本和删除状态；索引仅用于选择需要同步的主机，避免索引读取后数据变化导致误判。
- 继续读取旧版无版本号的 `host/group/key` 载荷；未知新版本或损坏结构报错并保留本机配置。
- 新客户端读取旧版 `v1:` 未压缩密文和新版 `v2:gzip:` 压缩密文；旧客户端读取新版压缩载荷前需要升级。服务端把载荷作为不透明密文保存，压缩和解密均在客户端完成。
- 配置修改时间与连接时间独立；服务端单进程全局串行处理数据库操作，修改时间仍用于避免旧配置覆盖新配置。
