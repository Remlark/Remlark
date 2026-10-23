import 'package:flutter/material.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:provider/provider.dart';

import '../../../app/theme/app_palette.dart';
import '../../../l10n/app_localizations.dart';
import '../../../utils/format_utils.dart';
import '../../settings/ui/settings_card.dart';
import '../updates_controller.dart';

/// 软件更新页：状态摘要、升级主操作、版本说明；鉴权复用本机 Git，不提供凭据输入。
class UpdatesSection extends StatelessWidget {
  const UpdatesSection({super.key});

  /// 根据检查、下载及失败状态呈现主要操作，使用换行布局适配窄窗口。
  @override
  Widget build(BuildContext context) {
    final u = context.watch<UpdatesController>();
    final p = context.palette;
    final busy = u.busy;
    final available = u.hasUpdate;
    final status = u.checking
        ? 'updates.checking'
        : u.downloading
        ? 'updates.downloading'
        : u.installing
        ? 'updates.installing'
        : u.error != null || u.outcome == 'updates.error.install'
        ? 'updates.attention'
        : u.hasUpdate
        ? 'updates.available'
        : u.currentVersion == 'development'
        ? 'updates.development'
        : u.release != null
        ? 'updates.latest'
        : 'updates.unchecked';
    return SettingsCard(
      title: context.tr('updates.title'),
      description: context.tr('updates.description'),
      children: [
        const SizedBox(height: 20),
        Container(
          padding: const EdgeInsets.all(22),
          decoration: BoxDecoration(
            color: p.input,
            border: Border.all(color: p.border),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Image.asset(
                    'assets/branding/app_icon.png',
                    width: 46,
                    height: 46,
                    excludeFromSemantics: true,
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          context.tr(status, {
                            'version': u.release?.version ?? '',
                          }),
                          style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.w700,
                            color: p.text,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          context.tr('updates.current', {
                            'version': u.currentVersion,
                          }),
                          style: TextStyle(color: p.textMuted),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 18),
              Text(
                context.tr('updates.source'),
                style: TextStyle(fontSize: 12, color: p.textMuted),
              ),
              if (u.checkedAt != null)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                    context.tr('updates.checked_at', {
                      'time': FormatUtils.dateTime(u.checkedAt!),
                    }),
                    style: TextStyle(fontSize: 12, color: p.textMuted),
                  ),
                ),
              if (u.checking || u.downloading || u.installing) ...[
                const SizedBox(height: 16),
                LinearProgressIndicator(
                  value: u.downloading && u.total > 0
                      ? (u.received / u.total).clamp(0.0, 1.0)
                      : null,
                ),
                if (u.downloading)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(
                      '${FormatUtils.bytes(u.received)} / ${FormatUtils.bytes(u.total)}',
                    ),
                  ),
              ],
              if (u.error != null)
                Padding(
                  padding: const EdgeInsets.only(top: 16),
                  child: Semantics(
                    liveRegion: true,
                    child: Text(
                      context.tr(u.error!),
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  ),
                ),
              if (u.outcome != null)
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: Text(context.tr(u.outcome!)),
                ),
              if (available)
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: Text(
                    context.tr('updates.upgrade_hint'),
                    style: TextStyle(color: p.textMuted),
                  ),
                ),
              if (available && u.asset == null)
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: Text(context.tr('updates.no_asset')),
                ),
              const SizedBox(height: 18),
              Wrap(
                spacing: 12,
                runSpacing: 10,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  if (available && u.asset != null)
                    FilledButton.icon(
                      onPressed: busy ? null : u.upgrade,
                      icon: const Icon(Icons.download_outlined, size: 18),
                      label: Text(context.tr('updates.upgrade')),
                    ),
                  if (available && u.asset != null)
                    TextButton(
                      onPressed: busy ? null : u.check,
                      child: Text(context.tr('updates.check')),
                    )
                  else
                    FilledButton.icon(
                      onPressed: busy ? null : u.check,
                      icon: const Icon(Icons.refresh_rounded, size: 18),
                      label: Text(context.tr('updates.check')),
                    ),
                ],
              ),
              if (available && u.asset != null)
                Padding(
                  padding: const EdgeInsets.only(top: 10),
                  child: Text(
                    '${u.asset!.name} · ${FormatUtils.bytes(u.asset!.size)}',
                    style: TextStyle(fontSize: 12, color: p.textMuted),
                  ),
                ),
            ],
          ),
        ),
        if (u.release != null) ...[
          SettingsGroupTitle(
            context.tr('updates.notes', {'version': u.release!.version}),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 16),
            child: MarkdownBody(
              selectable: true,
              imageBuilder: (_, _, _) => const SizedBox.shrink(),
              data: u.release!.notes.isEmpty
                  ? context.tr('updates.no_notes')
                  : u.release!.notes,
            ),
          ),
        ],
        SettingsRow(
          label: context.tr('updates.automatic'),
          description: context.tr('updates.automatic.desc'),
          child: Switch(
            value: u.automatic,
            onChanged: busy ? null : u.setAutomatic,
          ),
        ),
      ],
    );
  }
}
