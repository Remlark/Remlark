import 'package:path/path.dart' as p;

import '../../utils/platform_utils.dart';

/// ~/.ssh/config 中的一个 Host 条目
class SshConfigEntry {
  SshConfigEntry(this.alias);

  final String alias;
  String? hostName;
  String? user;
  int? port;
  String? identityFile;
  List<String> proxyJump = [];
}

/// OpenSSH 配置解析（仅解析常用字段）
class SshConfigParser {
  SshConfigParser._();

  /// 解析配置文本，忽略包含通配符的 Host 与 Match 块
  static List<SshConfigEntry> parse(String text) {
    final result = <SshConfigEntry>[];
    List<SshConfigEntry> current = [];
    for (var raw in text.split('\n')) {
      final line = raw.trim();
      if (line.isEmpty || line.startsWith('#')) continue;
      final m = RegExp(r'^(\S+)\s*=?\s*(.*)$').firstMatch(line);
      if (m == null) continue;
      final key = m.group(1)!.toLowerCase();
      final value = m.group(2)!.trim().replaceAll('"', '');
      if (key == 'host') {
        current = [
          for (final a in value.split(RegExp(r'\s+')))
            if (!a.contains('*') && !a.contains('?') && !a.startsWith('!')) SshConfigEntry(a),
        ];
        result.addAll(current);
        continue;
      }
      if (key == 'match') {
        current = [];
        continue;
      }
      for (final e in current) {
        switch (key) {
          case 'hostname':
            e.hostName = value;
          case 'user':
            e.user = value;
          case 'port':
            e.port = int.tryParse(value);
          case 'identityfile':
            e.identityFile ??= _expand(value);
          case 'proxyjump':
            if (value.toLowerCase() != 'none') {
              e.proxyJump = value.split(',').map((s) => s.trim().split('@').last.split(':').first).toList();
            }
        }
      }
    }
    return result;
  }

  static String _expand(String path) {
    if (path.startsWith('~/')) return p.join(PlatformUtils.homeDir(), path.substring(2));
    return path;
  }
}
