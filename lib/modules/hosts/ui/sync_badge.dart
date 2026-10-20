import 'package:flutter/material.dart';

import '../../../app/theme/app_palette.dart';
import '../../../l10n/app_localizations.dart';
import '../../../ui_kit/tags.dart';
import '../host_model.dart';

/// 同步状态：已同步 / 待同步 / 仅本地。[withText] 为 false 时只显示图标（带 tooltip）
class SyncBadge extends StatelessWidget {
  const SyncBadge({super.key, required this.state, this.withText = false});

  final SyncState state;
  final bool withText;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final (icon, color, key) = switch (state) {
      SyncState.synced => (Icons.check_circle_outline_rounded, p.success, 'sync.state.synced'),
      SyncState.pending => (Icons.schedule_rounded, p.warning, 'sync.state.pending'),
      SyncState.local => (Icons.computer_outlined, p.textMuted, 'sync.state.local'),
    };
    if (withText) return StatusText(text: context.tr(key), color: color, icon: icon);
    return Tooltip(
      message: context.tr(key),
      child: Icon(icon, size: 16, color: color),
    );
  }
}
