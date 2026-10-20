import 'package:flutter/material.dart';

import '../../../app/theme/app_palette.dart';
import '../../../l10n/app_localizations.dart';
import '../../workspace/workspace_tab.dart';

/// 远程桌面未连接时的状态视图：连接中 / 失败 / 断开，提供重新连接
class DesktopStatus extends StatelessWidget {
  const DesktopStatus({super.key, required this.tab});

  final WorkspaceTab tab;

  /// 把错误码转换为可读文本
  static String errorText(BuildContext context, String? error) => switch (error) {
    'cancelled' => context.tr('terminal.cancelled'),
    'wrong_password' => context.tr('ssh.error.wrong_password'),
    'rdp.lib_missing' => context.tr('rdp.lib_missing'),
    null => context.tr('terminal.disconnected'),
    _ => error,
  };

  @override
  Widget build(BuildContext context) {
    if (tab.state == SessionState.connecting) {
      return Center(
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const CircularProgressIndicator(),
              const SizedBox(height: 12),
              Text(context.tr('terminal.connecting', {'name': tab.host.name})),
            ],
          ),
        ),
      );
    }
    return Center(
      child: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                tab.state == SessionState.failed ? Icons.error_outline : Icons.link_off,
                size: 40,
                color: tab.state == SessionState.failed ? context.palette.danger : context.palette.warning,
              ),
              const SizedBox(height: 10),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 520),
                child: Text(errorText(context, tab.error), textAlign: TextAlign.center),
              ),
              const SizedBox(height: 12),
              FilledButton.icon(
                icon: const Icon(Icons.refresh, size: 16),
                label: Text(context.tr('terminal.reconnect')),
                onPressed: tab.reconnect,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 拖拽文件时覆盖在画面上的提示
class DropHint extends StatelessWidget {
  const DropHint({super.key, required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Positioned.fill(
      child: IgnorePointer(
        child: Container(
          margin: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: context.palette.accent.withValues(alpha: 0.12),
            border: Border.all(color: context.palette.accent, width: 1.5),
            borderRadius: BorderRadius.circular(12),
          ),
          alignment: Alignment.center,
          child: Text(
            text,
            style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w600),
          ),
        ),
      ),
    );
  }
}
