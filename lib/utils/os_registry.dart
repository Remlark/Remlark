/// 操作系统标识与图标目录；探测与界面共享，避免新增系统时两处列表不一致。
class OsRegistry {
  OsRegistry._();

  /// 每个标识对应一张随应用打包的真实品牌 Logo。
  static const ids = <String>{
    'ubuntu',
    'debian',
    'centos',
    'rhel',
    'fedora',
    'rocky',
    'almalinux',
    'alpine',
    'arch',
    'manjaro',
    'opensuse',
    'amzn',
    'kali',
    'linuxmint',
    'ol',
    'raspbian',
    'gentoo',
    'nixos',
    'macos',
    'windows',
    'linux',
    'openwrt',
    'void',
    'zorin',
    'endeavouros',
    'garuda',
    'cachyos',
    'azurelinux',
    'deepin',
    'freebsd',
    'openbsd',
    'netbsd',
    'sles',
    'slackware',
    'pop',
    'elementary',
    'devuan',
    'artix',
    'mx',
    'openeuler',
    'anolis',
    'uos',
    'kylin',
  };

  /// 不同版本或历史命名共享同一品牌图标。
  static const _aliases = <String, String>{
    'opensuse-leap': 'opensuse',
    'opensuse-tumbleweed': 'opensuse',
    'opensuse-microos': 'opensuse',
    'sled': 'sles',
    'suse': 'sles',
    'archlinux': 'arch',
    'redhat': 'rhel',
    'redhatenterpriseserver': 'rhel',
    'rockylinux': 'rocky',
    'oracle': 'ol',
    'pop_os': 'pop',
    'pop-os': 'pop',
    'voidlinux': 'void',
    'mxlinux': 'mx',
    'linux-mint': 'linuxmint',
    'kylinserver': 'kylin',
    'cbl-mariner': 'azurelinux',
  };

  /// 优先匹配系统本身；未知发行版按 ID_LIKE 的声明顺序逐项回退。
  static String normalize(String id, [String like = '']) {
    final value = id.trim().toLowerCase();
    final canonical = _aliases[value] ?? value;
    if (ids.contains(canonical)) return canonical;
    for (final parent in like.trim().toLowerCase().split(RegExp(r'\s+'))) {
      final candidate = _aliases[parent] ?? parent;
      if (ids.contains(candidate)) return candidate;
    }
    return value.isEmpty ? 'linux' : value;
  }

  /// 返回打包资源路径；无法确认系统身份时由界面显示通用图标。
  static String? assetFor(String id) {
    final canonical = normalize(id);
    return ids.contains(canonical) ? 'assets/os_icons/$canonical.png' : null;
  }
}
