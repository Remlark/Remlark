import 'dart:convert';

import 'package:dartssh2/dartssh2.dart';

import '../../utils/os_registry.dart';

/// 远程系统信息
class OsInfo {
  const OsInfo(this.id, this.name);

  /// 规范化的系统 id，例如 ubuntu、rhel、centos、debian、macos、windows
  final String id;

  /// 可读名称，例如 "Ubuntu 22.04.3 LTS"
  final String name;
}

/// 远程操作系统自动探测
class OsDetector {
  OsDetector._();

  /// 通过 SSH 执行探测命令并解析结果，失败返回 null
  static Future<OsInfo?> detect(SSHClient client) async {
    try {
      final out = await client
          .run(
            'uname -s 2>/dev/null; cat /etc/os-release 2>/dev/null || cat /usr/lib/os-release 2>/dev/null || sw_vers 2>/dev/null; echo __END__',
          )
          .timeout(const Duration(seconds: 8));
      return parse(utf8.decode(out, allowMalformed: true));
    } catch (_) {
      // Windows OpenSSH 默认 shell 为 cmd/powershell，上面的命令会报错，单独探测
      try {
        final out = await client.run('ver').timeout(const Duration(seconds: 5));
        final s = utf8.decode(out, allowMalformed: true);
        if (s.contains('Windows')) return OsInfo('windows', s.trim());
      } catch (_) {}
      return null;
    }
  }

  /// 解析探测命令输出
  static OsInfo? parse(String output) {
    if (output.contains('Microsoft Windows') ||
        output.contains('is not recognized')) {
      return const OsInfo('windows', 'Windows');
    }
    final lines = const LineSplitter().convert(output);
    final kernel = lines.isNotEmpty ? lines.first.trim() : '';
    final kv = <String, String>{};
    for (final l in lines) {
      final i = l.indexOf('=');
      if (i <= 0) continue;
      var v = l.substring(i + 1).trim();
      if (v.length >= 2 && (v.startsWith('"') || v.startsWith("'"))) {
        v = v.substring(1, v.length - 1);
      }
      kv[l.substring(0, i).trim()] = v;
    }
    if (kernel == 'Darwin') {
      final ver = lines
          .firstWhere((l) => l.startsWith('ProductVersion'), orElse: () => '')
          .split(':')
          .last
          .trim();
      return OsInfo('macos', 'macOS $ver'.trim());
    }
    if (kernel == 'FreeBSD' || kernel == 'OpenBSD' || kernel == 'NetBSD') {
      return OsInfo(kernel.toLowerCase(), kernel);
    }
    if (kv.isNotEmpty) {
      final id = normalizeId(kv['ID'] ?? '', kv['ID_LIKE'] ?? '');
      final name = kv['PRETTY_NAME'] ?? kv['NAME'] ?? id;
      return OsInfo(id, name);
    }
    if (kernel == 'Linux') return const OsInfo('linux', 'Linux');
    return null;
  }

  /// 将 os-release 的 ID 归一化为图标可识别的 id
  static String normalizeId(String id, String like) =>
      OsRegistry.normalize(id, like);
}
