import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../app/app_services.dart';
import '../../../app/theme/app_palette.dart';
import '../../../l10n/app_localizations.dart';
import '../../../ui_kit/app_dialog.dart';
import '../../../utils/id_utils.dart';
import '../../../utils/platform_utils.dart';
import '../../../utils/ui_utils.dart';
import '../key_model.dart';
import '../key_utils.dart';
import '../../../ui_kit/check_label.dart';

/// 密钥相关对话框：生成、导入
class KeyDialogs {
  KeyDialogs._();

  /// 生成 ed25519 密钥并保存，返回新密钥
  static Future<KeyEntry?> generate(BuildContext context) async {
    final name = await UiUtils.prompt(
      context,
      title: context.tr('key.generate'),
      label: context.tr('key.name'),
      initial: 'remlark-${DateTime.now().millisecondsSinceEpoch ~/ 1000}',
    );
    if (name == null || name.trim().isEmpty || !context.mounted) return null;
    final repo = context.read<AppServices>().keyRepo;
    final g = await KeyUtils.generateEd25519(name.trim());
    final k = KeyEntry(
      uuid: IdUtils.newId(),
      name: name.trim(),
      keyType: g.keyType,
      privateKey: g.privatePem,
      publicKey: g.publicLine,
      createdAt: DateTime.now().millisecondsSinceEpoch,
    );
    await repo.save(k);
    UiUtils.toast(S.of(UiUtils.context!).t('key.generated'));
    return k;
  }

  /// 导入私钥（文件或粘贴），返回新密钥
  static Future<KeyEntry?> import(BuildContext context) {
    return showDialog<KeyEntry>(context: context, builder: (_) => const _ImportKeyDialog());
  }
}

class _ImportKeyDialog extends StatefulWidget {
  const _ImportKeyDialog();

  @override
  State<_ImportKeyDialog> createState() => _ImportKeyDialogState();
}

class _ImportKeyDialogState extends State<_ImportKeyDialog> {
  final _name = TextEditingController();
  final _pem = TextEditingController();
  final _pass = TextEditingController();
  bool _savePass = true;
  String? _error;

  Future<void> _pickFile() async {
    final f = await openFile(initialDirectory: '${PlatformUtils.homeDir()}/.ssh');
    if (f == null) return;
    _pem.text = await File(f.path).readAsString();
    if (_name.text.isEmpty) _name.text = f.name;
    setState(() {});
  }

  Future<void> _save() async {
    final pem = _pem.text.trim();
    try {
      final encrypted = KeyUtils.isEncrypted(pem);
      final pub = KeyUtils.derivePublic(pem, encrypted ? _pass.text : null, _name.text.trim());
      final k = KeyEntry(
        uuid: IdUtils.newId(),
        name: _name.text.trim().isEmpty ? pub.keyType : _name.text.trim(),
        keyType: pub.keyType,
        privateKey: '$pem\n',
        passphrase: encrypted && _savePass ? _pass.text : null,
        publicKey: pub.publicLine,
        createdAt: DateTime.now().millisecondsSinceEpoch,
      );
      await context.read<AppServices>().keyRepo.save(k);
      if (mounted) Navigator.pop(context, k);
    } catch (e) {
      setState(() => _error = context.tr('key.import.invalid'));
    }
  }

  @override
  Widget build(BuildContext context) {
    final encrypted = _pem.text.isNotEmpty && KeyUtils.isEncrypted(_pem.text.trim());
    return AppDialog(
      icon: Icons.file_download_outlined,
      title: context.tr('key.import'),
      width: 620,
      content: SizedBox(
        width: 572,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _name,
                    decoration: InputDecoration(labelText: context.tr('key.name')),
                  ),
                ),
                const SizedBox(width: 12),
                OutlinedButton.icon(
                  onPressed: _pickFile,
                  icon: const Icon(Icons.folder_open, size: 16),
                  label: Text(context.tr('key.import.file')),
                ),
              ],
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _pem,
              maxLines: 8,
              onChanged: (_) => setState(() {}),
              style: const TextStyle(fontFamily: 'monospace', fontSize: 11),
              decoration: InputDecoration(labelText: context.tr('key.import.paste'), alignLabelWithHint: true),
            ),
            if (encrypted) ...[
              const SizedBox(height: 12),
              TextField(
                controller: _pass,
                obscureText: true,
                decoration: InputDecoration(labelText: context.tr('ssh.passphrase')),
              ),
              CheckLabel(
                value: _savePass,
                onChanged: (v) => setState(() => _savePass = v),
                label: context.tr('key.save_passphrase'),
              ),
            ],
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(_error!, style: TextStyle(color: context.palette.danger)),
              ),
          ],
        ),
      ),
      actions: [
        OutlinedButton(onPressed: () => Navigator.pop(context), child: Text(context.tr('common.cancel'))),
        FilledButton(onPressed: _pem.text.trim().isEmpty ? null : _save, child: Text(context.tr('key.import'))),
      ],
    );
  }
}
