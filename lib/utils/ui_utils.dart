import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';

/// UI 通用工具：全局 key、提示、确认框、输入框
class UiUtils {
  UiUtils._();

  /// 全局导航 key（非 Widget 代码中弹出对话框使用）
  static final navigatorKey = GlobalKey<NavigatorState>();

  /// 全局 SnackBar key
  static final messengerKey = GlobalKey<ScaffoldMessengerState>();

  /// 当前可用于弹框的 context
  static BuildContext? get context => navigatorKey.currentContext;

  /// 显示轻提示
  static void toast(String message, {bool error = false}) {
    final m = messengerKey.currentState;
    if (m == null) return;
    m.hideCurrentSnackBar();
    m.showSnackBar(
      SnackBar(
        content: Text(message),
        behavior: SnackBarBehavior.floating,
        width: 420,
        backgroundColor: error ? Colors.red.shade700 : null,
        duration: Duration(seconds: error ? 5 : 2),
      ),
    );
  }

  /// 确认对话框
  static Future<bool> confirm(
    BuildContext context, {
    required String title,
    String? message,
    String? okText,
    bool danger = false,
  }) async {
    final r = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: message == null ? null : Text(message),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(ctx.tr('common.cancel'))),
          FilledButton(
            style: danger ? FilledButton.styleFrom(backgroundColor: Colors.red.shade600) : null,
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(okText ?? ctx.tr('common.ok')),
          ),
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
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: SizedBox(
          width: 380,
          child: TextField(
            controller: ctrl,
            autofocus: true,
            obscureText: obscure,
            decoration: InputDecoration(labelText: label),
            onSubmitted: (v) => Navigator.pop(ctx, v),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: Text(ctx.tr('common.cancel'))),
          FilledButton(onPressed: () => Navigator.pop(ctx, ctrl.text), child: Text(ctx.tr('common.ok'))),
        ],
      ),
    );
  }
}
