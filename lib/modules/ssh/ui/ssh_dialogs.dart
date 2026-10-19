import 'package:dartssh2/dartssh2.dart';
import 'package:flutter/material.dart';

import '../../../l10n/app_localizations.dart';
import '../../../utils/ui_utils.dart';
import '../../hosts/host_model.dart';
import '../../remote_desktop/remote_desktop_interaction.dart';
import '../ssh_interaction.dart';

/// 基于对话框的交互实现，同时用于 SSH 与远程桌面（VNC / RDP）
class DialogInteraction extends SshInteraction implements RemoteDesktopInteraction {
  BuildContext get _ctx => UiUtils.context!;

  @override
  Future<PasswordInput?> askPassword(HostEntry host, {String? error}) {
    return showDialog<PasswordInput>(
      context: _ctx,
      barrierDismissible: false,
      builder: (_) => PasswordDialog(host: host, error: error),
    );
  }

  @override
  Future<PasswordInput?> askDesktopPassword(HostEntry host, {String? error}) => askPassword(host, error: error);

  @override
  Future<bool> confirmCertificateChanged(HostEntry host, String oldFingerprint, String newFingerprint) =>
      confirmHostKeyChanged(host, 'TLS', oldFingerprint, newFingerprint);

  @override
  Future<String?> askPassphrase(HostEntry host, {String? error}) async {
    final r = await showDialog<PasswordInput>(
      context: _ctx,
      barrierDismissible: false,
      builder: (_) => PasswordDialog(host: host, error: error, passphrase: true),
    );
    return r?.password;
  }

  @override
  Future<bool> confirmHostKeyChanged(
    HostEntry host,
    String keyType,
    String oldFingerprint,
    String newFingerprint,
  ) async {
    final ctx = _ctx;
    final r = await showDialog<bool>(
      context: ctx,
      barrierDismissible: false,
      builder: (c) => AlertDialog(
        icon: const Icon(Icons.warning_amber_rounded, color: Colors.orange, size: 36),
        title: Text(c.tr('ssh.hostkey.changed')),
        content: SizedBox(
          width: 480,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(c.tr('ssh.hostkey.warning', {'host': host.name})),
              const SizedBox(height: 12),
              SelectableText(
                '${c.tr('ssh.hostkey.old')}: $oldFingerprint',
                style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
              ),
              SelectableText(
                '${c.tr('ssh.hostkey.new')} ($keyType): $newFingerprint',
                style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: Text(c.tr('common.cancel'))),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.orange.shade700),
            onPressed: () => Navigator.pop(c, true),
            child: Text(c.tr('ssh.hostkey.accept')),
          ),
        ],
      ),
    );
    return r ?? false;
  }

  @override
  Future<List<String>?> keyboardInteractive(HostEntry host, SSHUserInfoRequest request) {
    final ctrls = [for (final _ in request.prompts) TextEditingController()];
    return showDialog<List<String>>(
      context: _ctx,
      barrierDismissible: false,
      builder: (c) => AlertDialog(
        title: Text(request.name.isEmpty ? host.name : request.name),
        content: SizedBox(
          width: 380,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (request.instruction.isNotEmpty) Text(request.instruction),
              for (var i = 0; i < request.prompts.length; i++)
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: TextField(
                    controller: ctrls[i],
                    autofocus: i == 0,
                    obscureText: !request.prompts[i].echo,
                    decoration: InputDecoration(labelText: request.prompts[i].promptText.trim()),
                  ),
                ),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c), child: Text(c.tr('common.cancel'))),
          FilledButton(
            onPressed: () => Navigator.pop(c, ctrls.map((e) => e.text).toList()),
            child: Text(c.tr('common.ok')),
          ),
        ],
      ),
    );
  }
}

/// 密码 / 口令输入对话框
class PasswordDialog extends StatefulWidget {
  const PasswordDialog({super.key, required this.host, this.error, this.passphrase = false});

  final HostEntry host;
  final String? error;
  final bool passphrase;

  @override
  State<PasswordDialog> createState() => _PasswordDialogState();
}

class _PasswordDialogState extends State<PasswordDialog> {
  final _ctrl = TextEditingController();
  bool _remember = false;
  bool _obscure = true;

  void _submit() => Navigator.pop(context, PasswordInput(_ctrl.text, remember: _remember));

  @override
  Widget build(BuildContext context) {
    final errorKey = switch (widget.error) {
      'wrong_password' => 'ssh.error.wrong_password',
      'key_rejected' => 'ssh.error.key_rejected',
      'wrong_passphrase' => 'ssh.error.wrong_passphrase',
      null => null,
      _ => null,
    };
    final errorText = errorKey != null ? context.tr(errorKey) : widget.error;
    return AlertDialog(
      title: Text(context.tr(widget.passphrase ? 'ssh.passphrase.title' : 'ssh.password.title')),
      content: SizedBox(
        width: 380,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(widget.host.endpoint, style: Theme.of(context).textTheme.bodySmall),
            if (errorText != null) ...[
              const SizedBox(height: 10),
              Row(
                children: [
                  const Icon(Icons.error_outline, color: Colors.red, size: 18),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(errorText, style: const TextStyle(color: Colors.red)),
                  ),
                ],
              ),
            ],
            const SizedBox(height: 14),
            TextField(
              controller: _ctrl,
              autofocus: true,
              obscureText: _obscure,
              onSubmitted: (_) => _submit(),
              decoration: InputDecoration(
                labelText: context.tr(widget.passphrase ? 'ssh.passphrase' : 'host.password'),
                suffixIcon: IconButton(
                  icon: Icon(_obscure ? Icons.visibility : Icons.visibility_off, size: 18),
                  onPressed: () => setState(() => _obscure = !_obscure),
                ),
              ),
            ),
            if (!widget.passphrase)
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                controlAffinity: ListTileControlAffinity.leading,
                value: _remember,
                onChanged: (v) => setState(() => _remember = v ?? false),
                title: Text(context.tr('host.remember_password')),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: Text(context.tr('common.cancel'))),
        FilledButton(onPressed: _submit, child: Text(context.tr('ssh.connect'))),
      ],
    );
  }
}
