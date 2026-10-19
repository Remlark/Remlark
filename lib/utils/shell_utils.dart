/// Shell 相关工具：参数转义、远程路径拼接
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
}
