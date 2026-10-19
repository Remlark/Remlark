import 'package:flutter/material.dart';

import '../host_model.dart';

/// 系统图标：根据自动探测到的系统 id 显示品牌色徽标，可区分 Ubuntu、RedHat 等发行版
class OsIcon extends StatelessWidget {
  const OsIcon({super.key, required this.host, this.size = 36});

  final HostEntry host;
  final double size;

  /// 系统 id -> (缩写, 品牌色)
  static const Map<String, (String, Color)> _brands = {
    'ubuntu': ('U', Color(0xFFE95420)),
    'debian': ('D', Color(0xFFA80030)),
    'centos': ('C', Color(0xFF932279)),
    'rhel': ('RH', Color(0xFFEE0000)),
    'fedora': ('F', Color(0xFF51A2DA)),
    'rocky': ('R', Color(0xFF10B981)),
    'almalinux': ('A', Color(0xFF0F4266)),
    'alpine': ('Al', Color(0xFF0D597F)),
    'arch': ('Ar', Color(0xFF1793D1)),
    'manjaro': ('M', Color(0xFF35BF5C)),
    'opensuse': ('S', Color(0xFF73BA25)),
    'sles': ('S', Color(0xFF0C322C)),
    'amzn': ('AWS', Color(0xFFFF9900)),
    'kali': ('K', Color(0xFF367BF0)),
    'linuxmint': ('Mi', Color(0xFF87CF3E)),
    'deepin': ('De', Color(0xFF0081FF)),
    'uos': ('UOS', Color(0xFF0066CC)),
    'openeuler': ('oE', Color(0xFF002FA7)),
    'kylin': ('Ky', Color(0xFFD32F2F)),
    'anolis': ('An', Color(0xFFFF6A00)),
    'ol': ('OL', Color(0xFFC74634)),
    'raspbian': ('Pi', Color(0xFFC51A4A)),
    'gentoo': ('G', Color(0xFF54487A)),
    'nixos': ('N', Color(0xFF5277C3)),
    'freebsd': ('BSD', Color(0xFFAB2B28)),
    'openbsd': ('BSD', Color(0xFFF2CA30)),
  };

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final id = host.osId;
    Widget child;
    Color bg;
    if (host.protocol == HostProtocol.rdp || id == 'windows') {
      bg = const Color(0xFF0078D4);
      child = Icon(Icons.window, color: Colors.white, size: size * 0.55);
    } else if (id == 'macos') {
      bg = const Color(0xFF555555);
      child = Icon(Icons.apple, color: Colors.white, size: size * 0.58);
    } else if (id != null && _brands.containsKey(id)) {
      final (abbr, color) = _brands[id]!;
      bg = color;
      child = Text(
        abbr,
        style: TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.w800,
          fontSize: size * (abbr.length > 2 ? 0.28 : 0.4),
        ),
      );
    } else if (host.protocol == HostProtocol.vnc) {
      bg = const Color(0xFF6D4C9F);
      child = Icon(Icons.desktop_windows_outlined, color: Colors.white, size: size * 0.55);
    } else if (id != null) {
      // 未知发行版：通用 Linux 图标
      bg = const Color(0xFF333333);
      child = Icon(Icons.terminal, color: Colors.amber, size: size * 0.55);
    } else {
      bg = scheme.surfaceContainerHighest;
      child = Icon(Icons.dns_outlined, color: scheme.onSurfaceVariant, size: size * 0.55);
    }
    return Tooltip(
      message: host.osName ?? host.protocol.name.toUpperCase(),
      child: Container(
        width: size,
        height: size,
        alignment: Alignment.center,
        decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(size * 0.26)),
        child: child,
      ),
    );
  }
}
