import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../../app/app_services.dart';
import '../../../app/theme/app_palette.dart';
import '../../../app/theme/app_theme.dart';
import '../../../l10n/app_localizations.dart';
import '../../../ui_kit/app_table.dart';
import '../../../ui_kit/buttons.dart';
import '../../../ui_kit/page_header.dart';
import '../../../ui_kit/panel.dart';
import '../../../ui_kit/tags.dart';
import '../../../utils/format_utils.dart';
import '../../../utils/ui_utils.dart';
import '../key_model.dart';
import '../key_repository.dart';
import '../key_utils.dart';
import 'key_dialogs.dart';

/// 密钥管理页：页头（导入、生成）+ 密钥表格 + 选中密钥的公钥详情
class KeysPage extends StatefulWidget {
  const KeysPage({super.key});

  @override
  State<KeysPage> createState() => _KeysPageState();
}

class _KeysPageState extends State<KeysPage> {
  List<KeyEntry> _keys = [];
  final Map<String, String> _fingerprints = {};
  String? _selected;
  late final KeyRepository _repo;

  @override
  void initState() {
    super.initState();
    // 页面常驻（IndexedStack），其他位置（如主机编辑器、同步、导入）增删密钥时也要刷新
    _repo = context.read<AppServices>().keyRepo..addListener(_load);
    _load();
  }

  @override
  void dispose() {
    _repo.removeListener(_load);
    super.dispose();
  }

  Future<void> _load() async {
    final keys = await _repo.list();
    for (final k in keys) {
      _fingerprints[k.uuid] ??= await KeyUtils.fingerprint(k.publicKey);
    }
    if (!mounted) return;
    setState(() {
      _keys = keys;
      if (_selected == null || !keys.any((k) => k.uuid == _selected)) _selected = keys.firstOrNull?.uuid;
    });
  }

  void _copy(String text) {
    Clipboard.setData(ClipboardData(text: text));
    UiUtils.toast(context.tr('common.copied'));
  }

  Future<void> _delete(KeyEntry k) async {
    final ok = await UiUtils.confirm(
      context,
      title: context.tr('key.delete'),
      message: context.tr('key.delete.message', {'name': k.name}),
      danger: true,
    );
    if (!ok || !mounted) return;
    await _repo.delete(k.uuid);
  }

  /// 密钥类型简称：ssh-ed25519 → ED25519
  static String _typeLabel(String t) => t.replaceFirst('ssh-', '').replaceFirst('ecdsa-sha2-', 'ECDSA ').toUpperCase();

  @override
  Widget build(BuildContext context) {
    final selected = _keys.where((k) => k.uuid == _selected).firstOrNull;
    return PageFrame(
      header: PageHeader(
        title: context.tr('key.page.title'),
        subtitle: context.tr('key.page.subtitle'),
        actions: [
          OutlinedButton.icon(
            icon: const Icon(Icons.file_download_outlined, size: 18),
            label: Text(context.tr('key.import')),
            onPressed: () async {
              final k = await KeyDialogs.import(context);
              if (k != null) {
                _selected = k.uuid;
                _load();
              }
            },
          ),
          FilledButton.icon(
            icon: const Icon(Icons.add, size: 18),
            label: Text(context.tr('key.generate')),
            onPressed: () async {
              final k = await KeyDialogs.generate(context);
              if (k != null) {
                _selected = k.uuid;
                _load();
              }
            },
          ),
        ],
      ),
      body: _keys.isEmpty
          ? EmptyState(icon: Icons.vpn_key_outlined, title: context.tr('key.empty'))
          : ListView(
              padding: const EdgeInsets.all(24),
              children: [
                _table(context),
                if (selected != null) ...[const SizedBox(height: 20), _detail(context, selected)],
              ],
            ),
    );
  }

  Widget _table(BuildContext context) {
    final p = context.palette;
    return LayoutBuilder(
      builder: (context, box) {
        final wide = box.maxWidth >= 900;
        final cols = [
          AppColumn(context.tr('key.name'), flex: 3),
          AppColumn(context.tr('key.type'), width: 120),
          if (wide) AppColumn(context.tr('key.fingerprint'), flex: 6),
          AppColumn(context.tr('key.created'), width: 160),
          AppColumn(context.tr('common.actions'), width: 84),
        ];
        return AppPanel(
          padding: EdgeInsets.zero,
          child: Column(
            children: [
              AppTableHeader(columns: cols, height: 48, padding: 14),
              for (final k in _keys)
                AppTableRow(
                  height: 60,
                  padding: 14,
                  columns: cols,
                  selected: k.uuid == _selected,
                  divider: k != _keys.last,
                  onTap: () => setState(() => _selected = k.uuid),
                  cells: [
                    Text(
                      k.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                    Tag(_typeLabel(k.keyType), color: k.keyType.contains('ed25519') ? p.accent : p.textMuted),
                    if (wide)
                      Text(
                        _fingerprints[k.uuid] ?? '',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 13, color: p.textMuted, fontFamily: 'monospace'),
                      ),
                    Text(
                      FormatUtils.dateTime(DateTime.fromMillisecondsSinceEpoch(k.createdAt)),
                      style: TextStyle(fontSize: 13, color: p.textMuted, fontFamily: 'monospace'),
                    ),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        GhostIconButton(
                          icon: Icons.copy_rounded,
                          tooltip: context.tr('key.copy_public'),
                          onPressed: () => _copy(k.publicKey),
                        ),
                        GhostIconButton(
                          icon: Icons.delete_outline,
                          tooltip: context.tr('common.delete'),
                          onPressed: () => _delete(k),
                        ),
                      ],
                    ),
                  ],
                ),
            ],
          ),
        );
      },
    );
  }

  /// 选中密钥详情：类型、指纹、创建时间、公钥全文
  Widget _detail(BuildContext context, KeyEntry k) {
    final p = context.palette;
    final label = TextStyle(fontSize: 13, color: p.textMuted);
    final fp = _fingerprints[k.uuid] ?? '';
    return AppPanel(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            k.name,
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: p.text),
          ),
          const SizedBox(height: 18),
          Wrap(
            spacing: 28,
            runSpacing: 12,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(context.tr('key.type'), style: label),
                  const SizedBox(width: 12),
                  Tag(_typeLabel(k.keyType)),
                ],
              ),
              if (fp.isNotEmpty)
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(context.tr('key.fingerprint'), style: label),
                    const SizedBox(width: 12),
                    Container(
                      padding: const EdgeInsets.only(left: 12),
                      decoration: BoxDecoration(
                        color: p.input,
                        borderRadius: BorderRadius.circular(AppSizes.radius),
                        border: Border.all(color: p.borderStrong),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            fp,
                            style: TextStyle(fontSize: 13, color: p.text, fontFamily: 'monospace'),
                          ),
                          GhostIconButton(
                            icon: Icons.copy_rounded,
                            tooltip: context.tr('common.copy'),
                            onPressed: () => _copy(fp),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(context.tr('key.created'), style: label),
                  const SizedBox(width: 12),
                  Text(
                    FormatUtils.dateTime(DateTime.fromMillisecondsSinceEpoch(k.createdAt)),
                    style: TextStyle(fontSize: 13, color: p.text, fontFamily: 'monospace'),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 20),
          Text(context.tr('key.public'), style: label),
          const SizedBox(height: 8),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Container(
                  constraints: const BoxConstraints(minHeight: 96),
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: p.input,
                    borderRadius: BorderRadius.circular(AppSizes.radius),
                    border: Border.all(color: p.borderStrong),
                  ),
                  child: SelectableText(
                    k.publicKey,
                    style: TextStyle(fontSize: 13, color: p.text, fontFamily: 'monospace', height: 1.6),
                  ),
                ),
              ),
              const SizedBox(width: 14),
              FilledButton.icon(
                icon: const Icon(Icons.copy_rounded, size: 17),
                label: Text(context.tr('key.copy_public')),
                onPressed: () => _copy(k.publicKey),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
