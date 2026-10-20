import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../app/theme/app_palette.dart';
import '../../../l10n/app_localizations.dart';
import '../../../ui_kit/app_menu.dart';
import '../../../ui_kit/panel.dart';
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
  bool _showToken = false;
  bool _showPass = false;

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
    final p = context.palette;
    final sync = context.watch<SyncService>();
    final hosts = context.watch<HostsController>().all;
    final synced = hosts.where((h) => h.syncState == SyncState.synced).length;
    final pending = hosts.where((h) => h.syncState == SyncState.pending).length;
    final local = hosts.where((h) => h.syncState == SyncState.local).length;
    final last = sync.config.lastSyncAt;
    return SettingsCard(
      title: context.tr('settings.sync'),
      description: context.tr('settings.sync.desc'),
      children: [
        const SizedBox(height: 20),
        Row(
          children: [
            Expanded(
              child: _stat(
                context,
                Icons.check_circle_outline_rounded,
                p.success,
                'sync.state.synced',
                'sync.state.synced.desc',
                synced,
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: _stat(
                context,
                Icons.schedule_rounded,
                p.warning,
                'sync.state.pending',
                'sync.state.pending.desc',
                pending,
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: _stat(
                context,
                Icons.computer_outlined,
                p.textMuted,
                'sync.state.local',
                'sync.state.local.desc',
                local,
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        AppPanel(
          padding: const EdgeInsets.fromLTRB(22, 20, 22, 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                context.tr('sync.config'),
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: p.text),
              ),
              const SizedBox(height: 18),
              _field(
                context,
                context.tr('sync.server'),
                context.tr('sync.server.helper'),
                TextField(
                  controller: _url,
                  style: const TextStyle(fontFamily: 'monospace'),
                  decoration: const InputDecoration(hintText: 'https://sync.example.com:8443'),
                ),
              ),
              _field(
                context,
                context.tr('sync.token'),
                context.tr('sync.token.helper'),
                TextField(
                  controller: _token,
                  obscureText: !_showToken,
                  decoration: InputDecoration(
                    suffixIcon: _eye(_showToken, () => setState(() => _showToken = !_showToken)),
                  ),
                ),
              ),
              _field(
                context,
                context.tr('sync.passphrase'),
                context.tr('sync.passphrase.helper'),
                TextField(
                  controller: _pass,
                  obscureText: !_showPass,
                  decoration: InputDecoration(
                    suffixIcon: _eye(_showPass, () => setState(() => _showPass = !_showPass)),
                  ),
                ),
              ),
              _field(
                context,
                context.tr('sync.interval'),
                context.tr('sync.interval.helper'),
                Align(
                  alignment: Alignment.centerLeft,
                  child: SizedBox(
                    width: 280,
                    child: AppDropdown<int>(
                      value: _interval,
                      items: [
                        for (final m in const [0, 5, 15, 30, 60, 180])
                          AppMenuItem(
                            value: m,
                            label: m == 0
                                ? context.tr('sync.interval.manual')
                                : context.tr('sync.interval.minutes', {'n': m}),
                          ),
                      ],
                      onChanged: (v) => setState(() => _interval = v ?? 0),
                    ),
                  ),
                ),
              ),
              const Divider(height: 28),
              Wrap(
                spacing: 10,
                runSpacing: 10,
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
                    child: Text(context.tr('sync.save')),
                  ),
                  OutlinedButton.icon(
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
                  const SizedBox(width: 12),
                  Text(
                    last == null
                        ? context.tr('sync.never')
                        : context.tr('sync.last', {
                            'time': FormatUtils.dateTime(DateTime.fromMillisecondsSinceEpoch(last)),
                          }),
                    style: TextStyle(fontSize: 13, color: p.textMuted),
                  ),
                ],
              ),
              if (sync.lastError != null)
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: Row(
                    children: [
                      Icon(Icons.error_outline, size: 18, color: p.danger),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(context.tr(sync.lastError!), style: TextStyle(color: p.danger)),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }

  /// 显示 / 隐藏密文
  Widget _eye(bool visible, VoidCallback onTap) => IconButton(
    tooltip: context.tr(visible ? 'common.hide' : 'common.show'),
    icon: Icon(visible ? Icons.visibility_off_outlined : Icons.visibility_outlined, size: 18),
    onPressed: onTap,
  );

  /// 左侧标签、右侧输入与说明
  Widget _field(BuildContext context, String label, String helper, Widget input) {
    final p = context.palette;
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 150,
            child: Padding(
              padding: const EdgeInsets.only(top: 11),
              child: Text(
                label,
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: p.text),
              ),
            ),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                input,
                const SizedBox(height: 6),
                Text(helper, style: TextStyle(fontSize: 12.5, color: p.textFaint)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// 状态统计卡
  Widget _stat(BuildContext context, IconData icon, Color color, String key, String descKey, int n) {
    final p = context.palette;
    return AppPanel(
      padding: const EdgeInsets.all(18),
      child: Row(
        children: [
          Icon(icon, size: 34, color: color),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(context.tr(key), style: TextStyle(fontSize: 13, color: p.textMuted)),
                Text(
                  '$n',
                  style: TextStyle(fontSize: 26, fontWeight: FontWeight.w700, color: p.text, height: 1.25),
                ),
                Text(
                  context.tr(descKey),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 12, color: p.textFaint),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
