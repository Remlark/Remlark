import 'dart:io';

/// 启动 Windows PowerShell 5.1 用的环境变量。
///
/// CI 在 pwsh 7 中运行测试，子进程会继承 7 的 PSModulePath，导致 5.1 加载不兼容的
/// 内置模块（如 Get-FileHash 不可用），并在命令查找时扫描大量模块而变慢。
/// 这里把模块路径重置为 5.1 自己的默认目录，并合并调用方的其他变量。
Map<String, String> windowsPowerShellEnvironment([
  Map<String, String> extra = const {},
]) {
  final systemRoot = Platform.environment['SystemRoot'] ?? r'C:\Windows';
  final programFiles =
      Platform.environment['ProgramFiles'] ?? r'C:\Program Files';
  return {
    'PSModulePath':
        '$programFiles\\WindowsPowerShell\\Modules;'
        '$systemRoot\\system32\\WindowsPowerShell\\v1.0\\Modules',
    ...extra,
  };
}
