import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../../app/app_services.dart';
import '../../../l10n/app_localizations.dart';
import '../../../utils/format_utils.dart';
import '../../../utils/ui_utils.dart';
import '../key_model.dart';
import 'key_dialogs.dart';

/// 密钥管理页：生成、导入、复制公钥、删除
class KeysPage extends StatefulWidget {
  const KeysPage({super.key});

  @override
  State<KeysPage> createState() => _KeysPageState();
}

class _KeysPageState extends State<KeysPage> {
  List<KeyEntry> _keys = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final keys = await context.read<AppServices>().keyRepo.list();
    if (mounted) setState(() => _keys = keys);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 18, 20, 14),
          child: Row(
            children: [
              Text(context.tr('nav.keys'), style: theme.textTheme.titleLarge),
              const Spacer(),
              IconButton(tooltip: context.tr('common.refresh'), onPressed: _load, icon: const Icon(Icons.refresh)),
              const SizedBox(width: 8),
              OutlinedButton.icon(
                icon: const Icon(Icons.file_open_outlined, size: 18),
                label: Text(context.tr('key.import')),
                onPressed: () async {
                  if (await KeyDialogs.import(context) != null) _load();
                },
              ),
              const SizedBox(width: 8),
              FilledButton.icon(
                icon: const Icon(Icons.auto_fix_high, size: 18),
                label: Text(context.tr('key.generate')),
                onPressed: () async {
                  if (await KeyDialogs.generate(context) != null) _load();
                },
              ),
            ],
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: _keys.isEmpty
              ? Center(child: Text(context.tr('key.empty')))
              : ListView.separated(
                  padding: const EdgeInsets.all(20),
                  itemCount: _keys.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 10),
                  itemBuilder: (context, i) {
                    final k = _keys[i];
                    return Card(
                      child: ListTile(
                        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                        leading: const CircleAvatar(child: Icon(Icons.key, size: 18)),
                        title: Text(k.name),
                        subtitle: Text(
                          '${k.keyType} · ${FormatUtils.dateTime(DateTime.fromMillisecondsSinceEpoch(k.createdAt))}\n${k.publicKey}',
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 11),
                        ),
                        isThreeLine: true,
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              tooltip: context.tr('key.copy_public'),
                              icon: const Icon(Icons.copy, size: 18),
                              onPressed: () {
                                Clipboard.setData(ClipboardData(text: k.publicKey));
                                UiUtils.toast(context.tr('common.copied'));
                              },
                            ),
                            IconButton(
                              tooltip: context.tr('common.delete'),
                              icon: const Icon(Icons.delete_outline, size: 18),
                              onPressed: () async {
                                final ok = await UiUtils.confirm(
                                  context,
                                  title: context.tr('key.delete'),
                                  message: context.tr('key.delete.message', {'name': k.name}),
                                  danger: true,
                                );
                                if (!ok || !context.mounted) return;
                                await context.read<AppServices>().keyRepo.delete(k.uuid);
                                _load();
                              },
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }
}
