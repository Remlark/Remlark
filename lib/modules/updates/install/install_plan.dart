import 'dart:io';

/// 已准备的安装助手：外部进程先握手，主程序退出后才修改安装目录。
class InstallPlan {
  const InstallPlan({
    required this.executable,
    required this.arguments,
    required this.directory,
  });
  final String executable;
  final List<String> arguments;
  final Directory directory;
  File get ready => File('${directory.path}/ready');
  File get result => File('${directory.path}/result');
}

/// 安装时固定使用快照，避免检查结果变化影响下载与安装目标。
class InstallContext {
  const InstallContext({
    required this.directory,
    required this.archive,
    required this.version,
    required this.executable,
    required this.processId,
  });
  final Directory directory;
  final File archive;
  final String version;
  final String executable;
  final int processId;
}
