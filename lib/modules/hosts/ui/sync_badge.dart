import 'package:flutter/material.dart';

import '../../../l10n/app_localizations.dart';
import '../host_model.dart';

/// 同步状态徽标：已同步 / 待同步 / 仅本地（仅本地时不显示）
class SyncBadge extends StatelessWidget {
  const SyncBadge({super.key, required this.state});

  final SyncState state;

  @override
  Widget build(BuildContext context) {
    final (icon, color, key) = switch (state) {
      SyncState.synced => (Icons.cloud_done_outlined, Colors.green, 'sync.state.synced'),
      SyncState.pending => (Icons.cloud_upload_outlined, Colors.orange, 'sync.state.pending'),
      SyncState.local => (Icons.cloud_off_outlined, Colors.grey, 'sync.state.local'),
    };
    return Tooltip(
      message: context.tr(key),
      child: Icon(icon, size: 16, color: color),
    );
  }
}
