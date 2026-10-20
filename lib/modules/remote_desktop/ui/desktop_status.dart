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
    final p = context.palette;
    // 远程画面可能是任意颜色（如资源管理器的白底）：先整体压暗，再用主题配色的卡片显示提示，保证可辨识
    return Positioned.fill(
      child: IgnorePointer(
        child: Container(
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.45),
            border: Border.all(color: p.accent, width: 3),
          ),
          alignment: Alignment.center,
          padding: const EdgeInsets.all(24),
          child: Container(
            constraints: const BoxConstraints(maxWidth: 460),
            padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 18),
            decoration: BoxDecoration(
              color: p.panelRaised,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: p.accent, width: 1.5),
              boxShadow: const [BoxShadow(color: Colors.black38, blurRadius: 24, offset: Offset(0, 8))],
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.file_download_outlined, size: 28, color: p.accent),
                const SizedBox(width: 14),
                Flexible(
                  child: Text(
                    text,
                    style: TextStyle(color: p.text, fontSize: 15, fontWeight: FontWeight.w600, height: 1.4),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
