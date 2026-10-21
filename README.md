# Remlark

跨平台（macOS / Linux / Windows）远程客户端：SSH / SFTP / RDP / VNC，内置 AI Agent 与可选的端到端加密同步服务。

- 需求与设计：[docs/design.md](docs/design.md)
- 开发步骤、构建命令与已知限制：[docs/design-steps.md](docs/design-steps.md)
- 编译环境、依赖安装与安装包构建：[docs/build-environment.md](docs/build-environment.md)

```bash
make run        # 运行
make            # 按当前平台打包到 dist/
make test       # 测试
make server     # 编译同步服务端
```

Windows 没有安装 GNU Make 时，在仓库根目录用 PowerShell 启动：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\windows\run.ps1
```

需要 Flutter 和 Visual Studio C++ 桌面工具；首次构建原生库的依赖见[编译环境文档](docs/build-environment.md)。修改原生代码后加 `-RebuildNative`。
