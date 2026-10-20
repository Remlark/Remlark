import 'package:flutter/material.dart';

import '../app/theme/app_palette.dart';
import '../l10n/app_localizations.dart';
import '../ui_kit/app_dialog.dart';
import '../ui_kit/buttons.dart';

/// UI 通用工具：全局 key、提示、确认框、输入框
class UiUtils {
  UiUtils._();

  /// 全局导航 key（非 Widget 代码中弹出对话框使用）
  static final navigatorKey = GlobalKey<NavigatorState>();

  /// 全局 SnackBar key
  static final messengerKey = GlobalKey<ScaffoldMessengerState>();

  /// 当前可用于弹框的 context
  static BuildContext? get context => navigatorKey.currentContext;

  /// 显示轻提示：成功 / 失败带图标，不只依赖颜色区分
  static void toast(String message, {bool error = false}) {
    final m = messengerKey.currentState;
    final ctx = context;
    if (m == null) return;
    final p = ctx?.palette;
    m.hideCurrentSnackBar();
    m.showSnackBar(
      SnackBar(
        content: Row(
          children: [
            Icon(
              error ? Icons.error_rounded : Icons.check_circle_rounded,
              size: 20,
              color: error ? p?.danger : p?.success,
            ),
            const SizedBox(width: 10),
            Expanded(child: Text(message)),
          ],
        ),
        behavior: SnackBarBehavior.floating,
        width: 420,
        duration: Duration(seconds: error ? 5 : 2),
      ),
    );
  }

  /// 确认对话框；[danger] 为破坏性操作（红色确认按钮 + 警示图标）
  static Future<bool> confirm(
    BuildContext context, {
    required String title,
    String? message,
    String? okText,
    bool danger = false,
  }) async {
    final r = await showDialog<bool>(
      context: context,
      builder: (ctx) => AppDialog(
        title: title,
        icon: danger ? Icons.delete_outline_rounded : null,
        iconColor: danger ? ctx.palette.danger : null,
        content: message == null ? const SizedBox.shrink() : Text(message, style: const TextStyle(height: 1.5)),
        actions: [
          OutlinedButton(onPressed: () => Navigator.pop(ctx, false), child: Text(ctx.tr('common.cancel'))),
          if (danger)
            DangerButton(label: okText ?? ctx.tr('common.delete'), onPressed: () => Navigator.pop(ctx, true))
          else
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(okText ?? ctx.tr('common.ok'))),
        ],
      ),
    );
    return r ?? false;
  }

  /// 单行输入对话框
  static Future<String?> prompt(
    BuildContext context, {
    required String title,
    String initial = '',
    String? label,
    bool obscure = false,
  }) {
    final ctrl = TextEditingController(text: initial);
    return showDialog<String>(
      context: context,
      builder: (ctx) => AppDialog(
        title: title,
        width: 440,
        content: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            if (label != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Text(label, style: TextStyle(fontSize: 13, color: ctx.palette.textMuted)),
              ),
            TextField(
              controller: ctrl,
              autofocus: true,
              obscureText: obscure,
              onSubmitted: (v) => Navigator.pop(ctx, v),
            ),
          ],
        ),
        actions: [
          OutlinedButton(onPressed: () => Navigator.pop(ctx), child: Text(ctx.tr('common.cancel'))),
          FilledButton(onPressed: () => Navigator.pop(ctx, ctrl.text), child: Text(ctx.tr('common.ok'))),
        ],
      ),
    );
  }
}
