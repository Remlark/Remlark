import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../l10n/app_localizations.dart';
import '../../../utils/format_utils.dart';
import '../../../utils/ui_utils.dart';
import '../../hosts/host_model.dart';
import '../../hosts/hosts_controller.dart';
import '../../sync/sync_config.dart';
import '../../sync/sync_service.dart';
import 'settings_card.dart';

/// 同步设置：服务器地址、令牌、加密口令、自动同步间隔、测试连接、立即同步、状态统计
class SyncSettingsSection extends StatefulWidget {
  const SyncSettingsSection({super.key});

  @override
  State<SyncSettingsSection> createState() => _SyncSettingsSectionState();
}

class _SyncSettingsSectionState extends State<SyncSettingsSection> {
  late final SyncService _sync = context.read<SyncService>();
  late final _url = TextEditingController(text: _sync.config.serverUrl);
  late final _token = TextEditingController(text: _sync.config.token);
  late final _pass = TextEditingController(text: _sync.config.passphrase);
  late int _interval = _sync.config.intervalMinutes;
  bool _busy = false;

  SyncConfig get _form => SyncConfig(
    serverUrl: _url.text.trim(),
    token: _token.text.trim(),
    passphrase: _pass.text,
    intervalMinutes: _interval,
    lastSyncAt: _sync.config.lastSyncAt,
  );

  Future<void> _do(Future<void> Function() f) async {
    setState(() => _busy = true);
    try {
      await f();
    } catch (e) {
      if (mounted) UiUtils.toast(context.tr(_sync.lastError ?? '$e'), error: true);
    }
    if (mounted) setState(() => _busy = false);
  }

  @override
  Widget build(BuildContext context) {
    final sync = context.watch<SyncService>();
    final hosts = context.watch<HostsController>().all;
    final synced = hosts.where((h) => h.syncState == SyncState.synced).length;
    final pending = hosts.where((h) => h.syncState == SyncState.pending).length;
    final local = hosts.where((h) => h.syncState == SyncState.local).length;
    return SettingsCard(
      title: context.tr('settings.sync'),
      children: [
        Text(context.tr('settings.sync.desc'), style: Theme.of(context).textTheme.bodySmall),
        const SizedBox(height: 12),
        TextField(
          controller: _url,
          decoration: InputDecoration(labelText: context.tr('sync.server'), hintText: 'https://sync.example.com:8443'),
        ),
        const SizedBox(height: 12),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: TextField(
                controller: _token,
                obscureText: true,
                decoration: InputDecoration(labelText: context.tr('sync.token')),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: TextField(
                controller: _pass,
                obscureText: true,
                decoration: InputDecoration(
                  labelText: context.tr('sync.passphrase'),
                  helperText: context.tr('sync.passphrase.helper'),
                ),
              ),
            ),
          ],
        ),
        SettingsRow(
          label: context.tr('sync.interval'),
          child: DropdownButton<int>(
            value: _interval,
            items: [
              for (final m in const [0, 5, 15, 30, 60, 180])
                DropdownMenuItem(
                  value: m,
                  child: Text(
                    m == 0 ? context.tr('sync.interval.manual') : context.tr('sync.interval.minutes', {'n': m}),
                  ),
                ),
            ],
            onChanged: (v) => setState(() => _interval = v ?? 0),
          ),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            OutlinedButton(
              onPressed: _busy
                  ? null
                  : () => _do(() async {
                      final tr = S.of(context);
                      await _sync.testConnection(_form);
                      UiUtils.toast(tr.t('sync.test.ok'));
                    }),
              child: Text(context.tr('sync.test')),
            ),
            FilledButton(
              onPressed: _busy
                  ? null
                  : () => _do(() async {
                      final tr = S.of(context);
                      await _sync.saveConfig(_form);
                      UiUtils.toast(tr.t('common.saved'));
                    }),
              child: Text(context.tr('common.save')),
            ),
            FilledButton.tonalIcon(
              icon: sync.syncing
                  ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.sync, size: 16),
              label: Text(context.tr('sync.now')),
              onPressed: _busy || sync.syncing || !sync.config.isConfigured
                  ? null
                  : () => _do(() async {
                      final tr = S.of(context);
                      final r = await _sync.syncNow();
                      UiUtils.toast(tr.t('sync.done', {'pushed': r.pushed, 'pulled': r.pulled}));
                    }),
            ),
            const SizedBox(width: 8),
            Text(
              sync.config.lastSyncAt == null
                  ? context.tr('sync.never')
                  : context.tr('sync.last', {
                      'time': FormatUtils.dateTime(DateTime.fromMillisecondsSinceEpoch(sync.config.lastSyncAt!)),
                    }),
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 16,
          children: [
            _stat(Icons.cloud_done_outlined, Colors.green, context.tr('sync.state.synced'), synced),
            _stat(Icons.cloud_upload_outlined, Colors.orange, context.tr('sync.state.pending'), pending),
            _stat(Icons.cloud_off_outlined, Colors.grey, context.tr('sync.state.local'), local),
          ],
        ),
        if (sync.lastError != null)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(context.tr(sync.lastError!), style: const TextStyle(color: Colors.red)),
          ),
      ],
    );
  }

  Widget _stat(IconData icon, Color color, String label, int n) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Icon(icon, size: 16, color: color),
      const SizedBox(width: 4),
      Text('$label: $n'),
    ],
  );
}
