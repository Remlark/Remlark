/// 版本号工具：规范化、从命令输出中提取、比较。
class VersionUtils {
  VersionUtils._();

  /// 去掉版本号前缀：`v24.11.1`、`dsh-v0.2.1` 都规范为 `24.11.1`、`0.2.1`
  static String normalize(String version) {
    final v = version.trim();
    final m = RegExp(r'\d+\.\d+').firstMatch(v);
    return m == null ? v : v.substring(m.start);
  }

  /// 从命令输出中取出版本号，例如 `dsh 0.2.1-rc.2` → `0.2.1-rc.2`；找不到返回 null
  static String? parseOutput(String output) {
    final m = RegExp(r'(\d+\.\d+(?:\.\d+)*(?:-[0-9A-Za-z.\-]+)?)').firstMatch(output);
    return m?.group(1);
  }

  /// 比较两个版本号（语义化版本）：a < b 返回负数，相等返回 0，a > b 返回正数。
  /// 数字部分逐段比较；数字相同时带预发布后缀（如 -rc.2）的较低，预发布后缀之间按段比较。
  static int compare(String a, String b) {
    final (numA, preA) = _split(a);
    final (numB, preB) = _split(b);
    for (var i = 0; i < numA.length || i < numB.length; i++) {
      final x = i < numA.length ? numA[i] : 0;
      final y = i < numB.length ? numB[i] : 0;
      if (x != y) return x.compareTo(y);
    }
    if (preA.isEmpty || preB.isEmpty) return preA.isEmpty == preB.isEmpty ? 0 : (preA.isEmpty ? 1 : -1);
    final pa = preA.split('.');
    final pb = preB.split('.');
    for (var i = 0; i < pa.length || i < pb.length; i++) {
      if (i >= pa.length) return -1;
      if (i >= pb.length) return 1;
      final x = int.tryParse(pa[i]);
      final y = int.tryParse(pb[i]);
      // 纯数字段按数值比较，数字段低于字母段，字母段按字典序
      final c = x != null && y != null
          ? x.compareTo(y)
          : x != null
          ? -1
          : y != null
          ? 1
          : pa[i].compareTo(pb[i]);
      if (c != 0) return c;
    }
    return 0;
  }

  /// 拆分为数字段与预发布后缀（构建元数据 +xxx 忽略）
  static (List<int>, String) _split(String v) {
    final s = normalize(v).split('+').first;
    final dash = s.indexOf('-');
    final core = dash < 0 ? s : s.substring(0, dash);
    final pre = dash < 0 ? '' : s.substring(dash + 1);
    return (core.split('.').map((e) => int.tryParse(e) ?? 0).toList(), pre);
  }
}
