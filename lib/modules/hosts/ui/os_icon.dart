import 'package:flutter/material.dart';

import '../../../utils/os_registry.dart';
import '../host_model.dart';

/// 系统图标：使用本地品牌 Logo，所有主机列表与会话入口共享。
class OsIcon extends StatelessWidget {
  /// 创建指定尺寸的系统图标。
  const OsIcon({super.key, required this.host, this.size = 36});

  final HostEntry host;
  final double size;

  /// 优先显示实际探测结果，只有未识别系统的 RDP 主机才默认显示 Windows。
  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final id =
        host.osId ?? (host.protocol == HostProtocol.rdp ? 'windows' : null);
    final asset = id == null ? null : OsRegistry.assetFor(id);
    final label = host.osName ?? host.protocol.name.toUpperCase();
    // 品牌图标统一使用浅色底板，黑色 Logo 在深色主题中仍然清晰。
    final background = asset == null
        ? scheme.surfaceContainerHighest
        : const Color(0xFFF5F6F7);
    return Tooltip(
      message: label,
      child: Container(
        width: size,
        height: size,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: background,
          borderRadius: BorderRadius.circular(size * 0.26),
        ),
        child: asset != null
            ? Image.asset(
                asset,
                width: size,
                height: size,
                semanticLabel: label,
              )
            : Icon(
                id != null
                    ? Icons.terminal
                    : host.protocol == HostProtocol.vnc
                    ? Icons.desktop_windows_outlined
                    : Icons.dns_outlined,
                color: scheme.onSurfaceVariant,
                size: size * 0.55,
                semanticLabel: label,
              ),
      ),
    );
  }
}
