# Remlark

跨平台（macOS / Linux / Windows）远程客户端：SSH / SFTP / RDP / VNC，内置 AI Agent 与可选的端到端加密同步服务。

- 需求与设计：[docs/design.md](docs/design.md)
- 开发步骤、构建命令与已知限制：[docs/design-steps.md](docs/design-steps.md)

```bash
make run        # 运行
make            # 按当前平台打包到 dist/
make test       # 测试
make server     # 编译同步服务端
```
