import 'package:flutter/material.dart';

import '../../../utils/os_registry.dart';
import '../host_model.dart';

/// 系统图标：使用本地品牌 Logo，所有主机列表与会话入口共享。
class OsIcon extends StatelessWidget {
  /// 创建指定尺寸的系统图标。
  const OsIcon({super.key, required this.host, this.size = 36});

  final HostEntry host;
  final double size;

  /// 手动指定优先，其次采用 SSH 探测结果或名称中的明确系统标识。
  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final override = host.extra['osOverride'];
    final id = override is String && OsRegistry.ids.contains(override)
        ? override
        : host.osId ??
              OsRegistry.inferFromLabel(host.osName ?? '') ??
              OsRegistry.inferFromLabel(host.name);
    final asset = id == null ? null : OsRegistry.assetFor(id);
    final label = override is String && OsRegistry.ids.contains(override)
        ? OsRegistry.displayName(override)
        : host.osName ??
              (id == null
                  ? host.protocol.name.toUpperCase()
                  : OsRegistry.displayName(id));
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
