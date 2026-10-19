import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:provider/provider.dart';

import '../../../app/app_services.dart';
import '../../../l10n/app_localizations.dart';
import '../../../utils/format_utils.dart';
import '../../../utils/platform_utils.dart';
import '../../../utils/ui_utils.dart';
import '../../import_export/import_export_service.dart';
import 'settings_card.dart';

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
        builder: (ctx, setState) => AlertDialog(
          title: Text(ctx.tr('data.export')),
          content: SizedBox(
            width: 420,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  controlAffinity: ListTileControlAffinity.leading,
                  value: withSecrets,
                  onChanged: (v) => setState(() => withSecrets = v ?? false),
                  title: Text(ctx.tr('data.export.secrets')),
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
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(ctx.tr('common.cancel'))),
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
      final r = await services.importExport.importSshConfig(f.path, groupUuid: services.hosts.selectedGroup);
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
    return SettingsCard(
      title: context.tr('settings.data'),
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            OutlinedButton.icon(
              icon: const Icon(Icons.upload_file, size: 16),
              label: Text(context.tr('data.export')),
              onPressed: () => _export(context),
            ),
            OutlinedButton.icon(
              icon: const Icon(Icons.download, size: 16),
              label: Text(context.tr('data.import')),
              onPressed: () => _import(context),
            ),
            OutlinedButton.icon(
              icon: const Icon(Icons.terminal, size: 16),
              label: Text(context.tr('data.import_ssh_config')),
              onPressed: () => _importSshConfig(context),
            ),
          ],
        ),
      ],
    );
  }
}
