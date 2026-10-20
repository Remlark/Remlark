import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:provider/provider.dart';

import '../../../app/app_services.dart';
import '../../../l10n/app_localizations.dart';
import '../../../ui_kit/app_dialog.dart';
import '../../../utils/app_log.dart';
import '../../../utils/format_utils.dart';
import '../../../utils/platform_utils.dart';
import '../../../utils/ui_utils.dart';
import '../../import_export/import_export_service.dart';
import 'settings_card.dart';
import '../../../ui_kit/check_label.dart';

/// 数据：批量导出 / 导入（JSON，可选口令加密），从 ~/.ssh/config 导入
class DataSection extends StatelessWidget {
  const DataSection({super.key});

  Future<void> _export(BuildContext context) async {
    final services = context.read<AppServices>();
    var withSecrets = false;
    final pass = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setState) => AppDialog(
          title: ctx.tr('data.export'),
          icon: Icons.upload_file_outlined,
          content: SizedBox(
            width: 420,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                CheckLabel(
                  value: withSecrets,
                  onChanged: (v) => setState(() => withSecrets = v),
                  label: ctx.tr('data.export.secrets'),
                ),
                TextField(
                  controller: pass,
                  obscureText: true,
                  decoration: InputDecoration(
                    labelText: ctx.tr('data.export.passphrase'),
                    helperText: ctx.tr('data.export.passphrase.helper'),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            OutlinedButton(onPressed: () => Navigator.pop(ctx, false), child: Text(ctx.tr('common.cancel'))),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(ctx.tr('data.export'))),
          ],
        ),
      ),
    );
    if (ok != true || !context.mounted) return;
    if (withSecrets && pass.text.isEmpty) {
      final go = await UiUtils.confirm(context, title: context.tr('data.export.plain_warning'));
      if (!go) return;
    }
    final loc = await getSaveLocation(suggestedName: 'remlark-${FormatUtils.dayKey(DateTime.now())}.json');
    if (loc == null) return;
    try {
      await services.importExport.export(loc.path, withSecrets: withSecrets, passphrase: pass.text);
      UiUtils.toast(S.of(UiUtils.context!).t('data.export.done'));
    } catch (e) {
      UiUtils.toast('$e', error: true);
    }
  }

  Future<void> _import(BuildContext context) async {
    final services = context.read<AppServices>();
    final f = await openFile(
      acceptedTypeGroups: [
        const XTypeGroup(label: 'JSON', extensions: ['json']),
      ],
    );
    if (f == null || !context.mounted) return;
    String? pass;
    try {
      if (await services.importExport.isEncrypted(f.path)) {
        if (!context.mounted) return;
        pass = await UiUtils.prompt(context, title: context.tr('data.import.passphrase'), obscure: true);
        if (pass == null) return;
      }
      final r = await services.importExport.import(f.path, passphrase: pass);
      await services.hosts.load();
      _report(r);
    } catch (e) {
      UiUtils.toast('$e', error: true);
    }
  }

  Future<void> _importSshConfig(BuildContext context) async {
    final services = context.read<AppServices>();
    final path = p.join(PlatformUtils.homeDir(), '.ssh', 'config');
    final f = await openFile(initialDirectory: p.dirname(path));
    if (f == null) return;
    try {
      final r = await services.importExport.importSshConfig(f.path, groupUuid: services.hosts.selectedGroupUuid);
      await services.hosts.load();
      _report(r);
    } catch (e) {
      UiUtils.toast('$e', error: true);
    }
  }

  void _report(ImportResult r) {
    UiUtils.toast(
      S.of(UiUtils.context!).t('data.import.done', {
        'hosts': r.hosts,
        'keys': r.keys,
        'snippets': r.snippets,
        'skipped': r.skipped,
      }),
    );
  }

  @override
  Widget build(BuildContext context) {
    Widget action(IconData icon, String key, VoidCallback onPressed) =>
        OutlinedButton.icon(icon: Icon(icon, size: 17), label: Text(context.tr(key)), onPressed: onPressed);
    return SettingsCard(
      title: context.tr('settings.data'),
      description: context.tr('settings.data.desc'),
      children: [
        SettingsRow(
          label: context.tr('data.export'),
          description: context.tr('data.export.desc'),
          child: action(Icons.upload_file_outlined, 'data.export', () => _export(context)),
        ),
        SettingsRow(
          label: context.tr('data.import'),
          description: context.tr('data.import.desc'),
          child: action(Icons.file_download_outlined, 'data.import', () => _import(context)),
        ),
        SettingsRow(
          label: context.tr('data.import_ssh_config'),
          description: context.tr('data.import_ssh_config.desc'),
          child: action(Icons.terminal_rounded, 'data.import_ssh_config.button', () => _importSshConfig(context)),
        ),
        // 运行日志：排查连接、远程桌面卡顿、上传等问题时打开日志文件夹
        SettingsRow(
          label: context.tr('data.logs'),
          description: context.tr('data.logs.desc', {'path': AppLog.directory?.path ?? '-'}),
          child: action(Icons.article_outlined, 'data.logs.open', () async {
            final dir = AppLog.directory;
            if (dir == null) return;
            await AppLog.flush();
            await PlatformUtils.openInFileManager(dir.path);
          }),
        ),
      ],
    );
  }
}
