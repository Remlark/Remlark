/// Shell 相关工具：参数转义、远程路径拼接、重名处理
class ShellUtils {
  ShellUtils._();

  /// 单引号转义，生成可安全拼接到 POSIX shell 命令中的参数
  static String quote(String s) => "'${s.replaceAll("'", "'\\''")}'";

  /// 拼接远程（POSIX）路径
  static String joinRemote(String dir, String name) {
    if (dir.isEmpty) return name;
    if (dir.endsWith('/')) return '$dir$name';
    return '$dir/$name';
  }

  /// 远程路径的父目录
  static String parentRemote(String path) {
    if (path == '/' || path.isEmpty) return '/';
    var p = path.endsWith('/') ? path.substring(0, path.length - 1) : path;
    final idx = p.lastIndexOf('/');
    if (idx <= 0) return '/';
    return p.substring(0, idx);
  }

  /// 远程路径的文件名（最后一段）
  static String basenameRemote(String path) {
    final p = path.endsWith('/') && path.length > 1 ? path.substring(0, path.length - 1) : path;
    return p.substring(p.lastIndexOf('/') + 1);
  }

  /// 生成不与 [existing] 重名的名称，规则同 Finder：“名称 2.扩展名”“名称 3.扩展名”…
  /// 目录或无扩展名时直接追加序号
  static String uniqueName(String name, Set<String> existing, {bool isDir = false}) {
    if (!existing.contains(name)) return name;
    final dot = name.lastIndexOf('.');
    final hasExt = !isDir && dot > 0;
    final base = hasExt ? name.substring(0, dot) : name;
    final ext = hasExt ? name.substring(dot) : '';
    for (var i = 2; ; i++) {
      final candidate = '$base $i$ext';
      if (!existing.contains(candidate)) return candidate;
    }
  }
}
