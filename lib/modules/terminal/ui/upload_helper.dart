import 'package:flutter/material.dart';

import '../../../l10n/app_localizations.dart';
import '../../../utils/ui_utils.dart';
import '../../workspace/workspace_tab.dart';
import '../terminal_session.dart';

/// 终端上传辅助：拖拽或右键粘贴文件时，确认远程目标目录后加入传输队列
class UploadHelper {
  UploadHelper._();

  /// 上传本地文件 / 目录到会话所在服务器
  static Future<void> upload(BuildContext context, TerminalSession session, List<String> paths) async {
    if (paths.isEmpty) return;
    final sftp = session.sftp;
    final transfers = session.transfers;
    if (session.state != SessionState.connected || sftp == null || transfers == null) {
      UiUtils.toast(context.tr('terminal.not_connected'), error: true);
      return;
    }
    String dir;
    try {
      dir = session.lastRemoteDir ?? await sftp.home();
    } catch (e) {
      UiUtils.toast('$e', error: true);
      return;
    }
    if (!context.mounted) return;
    final names = paths.map((p) => p.split(RegExp(r'[/\\]')).last).join(', ');
    final target = await UiUtils.prompt(
      context,
      title: context.tr('upload.confirm', {'count': paths.length}),
      label: '${context.tr('upload.target')} · $names',
      initial: dir,
    );
    if (target == null || target.trim().isEmpty) return;
    session.lastRemoteDir = target.trim();
    for (final p in paths) {
      transfers.upload(p, target.trim());
    }
    UiUtils.toast(S.of(UiUtils.context!).t('upload.queued', {'count': paths.length}));
  }
}
