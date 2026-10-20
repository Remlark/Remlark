/// 只读命令判断（“只读自动执行”权限使用）。
///
/// 保守规则：无法确定的一律视为非只读（仍需用户确认）。
/// - 不允许输出重定向（`2>&1`、`>/dev/null` 除外）、命令替换、后台执行、sudo；
/// - 按 `|`、`&&`、`||`、`;`、换行拆分，每一段都必须是只读命令；
/// - 只读命令为白名单，部分命令只允许查看类子命令或禁止修改类参数（如 `sed -i`、`find -delete`）。
class ReadOnlyCommands {
  ReadOnlyCommands._();

  /// 任意参数都只读的命令
  static const _always = {
    'ls', 'll', 'cat', 'tac', 'head', 'tail', 'wc', 'grep', 'egrep', 'fgrep', 'zgrep', 'zcat', 'rg',
    'stat', 'file', 'du', 'df', 'free', 'uptime', 'uname', 'hostname', 'whoami', 'id', 'groups', 'w', 'who',
    'last', 'lastlog', 'date', 'cal', 'ps', 'pgrep', 'pstree', 'lsblk', 'lscpu', 'lsmem', 'lsof', 'lspci',
    'lsusb', 'findmnt', 'ss', 'netstat', 'ping', 'dig', 'nslookup', 'host', 'traceroute', 'tracepath',
    'printenv', 'echo', 'printf', 'pwd', 'which', 'whereis', 'type', 'realpath', 'readlink', 'basename',
    'dirname', 'sort', 'uniq', 'cut', 'jq', 'tr', 'column', 'diff', 'cmp', 'md5sum', 'sha1sum', 'sha256sum',
    'sha512sum', 'test', 'true', 'getent', 'dmesg', 'vmstat', 'iostat', 'mpstat', 'sar', 'nproc', 'arch',
    'nl', 'less', 'more', 'tree', 'locale',
  };

  /// 只允许以下子命令（第一个非选项参数）的命令；空集合表示不带子命令时只读
  static const _subcommands = {
    'systemctl': {'status', 'is-active', 'is-enabled', 'is-failed', 'list-units', 'list-unit-files', 'list-timers', 'list-sockets', 'show', 'cat'},
    'service': {'status'},
    'docker': {'ps', 'images', 'logs', 'inspect', 'stats', 'version', 'info', 'top', 'port', 'network', 'volume', 'compose'},
    'kubectl': {'get', 'describe', 'logs', 'top', 'version', 'cluster-info', 'explain', 'api-resources', 'config'},
    'git': {'status', 'log', 'diff', 'show', 'remote', 'rev-parse', 'blame', 'ls-files'},
    'ip': {'a', 'addr', 'address', 'r', 'route', 'link', 'l', 'neigh', 'n', 'rule', '-s', '-br', '-c', '-4', '-6'},
    'timedatectl': {'status', 'show'},
    'hostnamectl': {'status'},
    'journalctl': <String>{},
    'mount': <String>{},
    'crontab': <String>{},
    'nginx': <String>{},
    'find': <String>{},
    'sed': <String>{},
    'top': <String>{},
  };

  /// 命令替换、进程替换、后台执行等无法静态判断的写法
  static final _unsafe = RegExp(r'`|\$\(|<\(|>\(|(^|[^&])&($|[^&>])');

  /// 允许的无害重定向
  static final _harmlessRedirect = RegExp(r'\d?>\s*/dev/null|\d?>&\d|&>\s*/dev/null');

  /// [command] 是否可以视为只读
  static bool isReadOnly(String command) {
    var c = command.trim();
    if (c.isEmpty) return false;
    c = c.replaceAll(_harmlessRedirect, ' ');
    if (c.contains('>') || _unsafe.hasMatch(c)) return false;
    final segments = c.split(RegExp(r'\|\||&&|[|;\n]'));
    return segments.every((s) => s.trim().isEmpty || _segment(_words(s)));
  }

  /// 判断单个命令（已拆成词）
  static bool _segment(List<String> words) {
    var w = words;
    // 跳过环境变量赋值（FOO=bar cmd）
    while (w.isNotEmpty && RegExp(r'^[A-Za-z_][A-Za-z0-9_]*=').hasMatch(w.first)) {
      w = w.sublist(1);
    }
    if (w.isEmpty) return true;
    final name = w.first.split('/').last;
    final args = w.sublist(1);
    // 包装命令（timeout 10 cmd / nice cmd / env A=b cmd）：判断被包装的命令；env 单独使用时只是打印环境变量
    if (name == 'timeout' || name == 'nice' || name == 'env') {
      final rest = args
          .skipWhile((a) => a.startsWith('-') || RegExp(r'^\d').hasMatch(a) || (name == 'env' && a.contains('=')))
          .toList();
      return rest.isEmpty ? name == 'env' : _segment(rest);
    }
    if (_always.contains(name)) return true;
    final allowed = _subcommands[name];
    if (allowed == null) return false;
    switch (name) {
      case 'find':
        return !args.any((a) => const {'-delete', '-exec', '-execdir', '-ok', '-okdir', '-fprint', '-fprintf', '-fls'}.contains(a));
      case 'sed':
        return !args.any((a) => a == '-i' || a.startsWith('-i') || a == '--in-place' || a.startsWith('--in-place='));
      case 'top':
        return args.any((a) => a == '-b' || (a.startsWith('-') && a.contains('b')));
      case 'journalctl':
        return !args.any((a) => a.startsWith('--vacuum') || a == '--rotate' || a == '--flush' || a == '--sync');
      case 'mount':
        return args.isEmpty;
      case 'crontab':
        return args.length == 1 && args.first == '-l';
      case 'nginx':
        return args.isNotEmpty && args.every((a) => a == '-t' || a == '-T' || a == '-v' || a == '-V');
      case 'git':
        final sub = _firstNonOption(args);
        if (sub == 'remote') return args.length <= 2 && (args.length == 1 || args[1] == '-v');
        return sub != null && allowed.contains(sub);
      case 'docker':
        final sub = _firstNonOption(args);
        if (sub == 'network' || sub == 'volume') {
          final op = _firstNonOption(args.skip(args.indexOf(sub!) + 1).toList());
          return op == 'ls' || op == 'inspect';
        }
        if (sub == 'compose') {
          final op = _firstNonOption(args.skip(args.indexOf('compose') + 1).toList());
          return const {'ps', 'logs', 'config', 'top', 'images', 'ls'}.contains(op);
        }
        if (sub == 'stats') return args.contains('--no-stream');
        return sub != null && allowed.contains(sub);
      case 'kubectl':
        final sub = _firstNonOption(args);
        if (sub == 'config') return args.contains('view') || args.contains('get-contexts') || args.contains('current-context');
        return sub != null && allowed.contains(sub);
      case 'ip':
        // ip [选项] 对象 [show|list]：出现 add / del / set / flush 等修改操作则不是只读
        const writes = {'add', 'del', 'delete', 'set', 'flush', 'change', 'replace', 'append', 'save', 'restore'};
        return args.isNotEmpty && allowed.contains(args.first) && !args.any(writes.contains);
      case 'timedatectl':
      case 'hostnamectl':
        final sub = _firstNonOption(args);
        return sub == null || allowed.contains(sub);
      default:
        final sub = _firstNonOption(args);
        return sub != null && allowed.contains(sub);
    }
  }

  /// 第一个非选项参数
  static String? _firstNonOption(List<String> args) {
    for (final a in args) {
      if (!a.startsWith('-')) return a;
    }
    return null;
  }

  /// 按空白拆词，支持单双引号
  static List<String> _words(String s) {
    final out = <String>[];
    for (final m in RegExp(r'''"([^"]*)"|'([^']*)'|(\S+)''').allMatches(s)) {
      out.add(m.group(1) ?? m.group(2) ?? m.group(3)!);
    }
    return out;
  }
}
