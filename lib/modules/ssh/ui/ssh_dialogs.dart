import 'package:dartssh2/dartssh2.dart';
import 'package:flutter/material.dart';

import '../../../app/theme/app_palette.dart';
import '../../../l10n/app_localizations.dart';
import '../../../ui_kit/app_dialog.dart';
import '../../../ui_kit/panel.dart';
import '../../../utils/ui_utils.dart';
import '../../hosts/host_model.dart';
import '../../remote_desktop/remote_desktop_interaction.dart';
import '../ssh_interaction.dart';
import '../../../ui_kit/check_label.dart';

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
  Future<PasswordInput?> askDesktopPassword(HostEntry host, {String? error, bool askUsername = false}) {
    return showDialog<PasswordInput>(
      context: _ctx,
      barrierDismissible: false,
      builder: (_) => PasswordDialog(host: host, error: error, askUsername: askUsername),
    );
  }

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
      builder: (c) => AppDialog(
        icon: Icons.gpp_maybe_outlined,
        iconColor: c.palette.warning,
        title: c.tr('ssh.hostkey.changed'),
        width: 560,
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(c.tr('ssh.hostkey.warning', {'host': host.name})),
            const SizedBox(height: 16),
            _FingerprintBox(label: c.tr('ssh.hostkey.old'), value: oldFingerprint),
            const SizedBox(height: 10),
            _FingerprintBox(label: '${c.tr('ssh.hostkey.new')} ($keyType)', value: newFingerprint, highlight: true),
          ],
        ),
        actions: [
          OutlinedButton(onPressed: () => Navigator.pop(c, false), child: Text(c.tr('common.cancel'))),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: c.palette.warning, foregroundColor: Colors.black),
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
      builder: (c) => AppDialog(
        icon: Icons.keyboard_outlined,
        title: request.name.isEmpty ? host.name : request.name,
        content: SizedBox(
          width: 400,
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
          OutlinedButton(onPressed: () => Navigator.pop(c), child: Text(c.tr('common.cancel'))),
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
  const PasswordDialog({super.key, required this.host, this.error, this.passphrase = false, this.askUsername = false});

  final HostEntry host;
  final String? error;
  final bool passphrase;

  /// 是否同时输入用户名（预填主机已配置的用户名）
  final bool askUsername;

  @override
  State<PasswordDialog> createState() => _PasswordDialogState();
}

class _PasswordDialogState extends State<PasswordDialog> {
  final _ctrl = TextEditingController();
  late final _user = TextEditingController(text: widget.host.username);
  bool _remember = false;
  bool _obscure = true;

  void _submit() => Navigator.pop(
    context,
    PasswordInput(_ctrl.text, remember: _remember, username: widget.askUsername ? _user.text.trim() : null),
  );

  @override
  void dispose() {
    _ctrl.dispose();
    _user.dispose();
    super.dispose();
  }

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
    final p = context.palette;
    return AppDialog(
      icon: widget.passphrase ? Icons.vpn_key_outlined : Icons.lock_outline_rounded,
      title: context.tr(widget.passphrase ? 'ssh.passphrase.title' : 'ssh.password.title'),
      content: SizedBox(
        width: 400,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${widget.host.name}  ·  ${widget.host.endpoint}',
              style: TextStyle(fontSize: 13, color: p.textMuted, fontFamily: 'monospace'),
            ),
            if (errorText != null) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                decoration: BoxDecoration(
                  color: p.dangerSoft,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: p.danger.withValues(alpha: 0.4)),
                ),
                child: Row(
                  children: [
                    Icon(Icons.error_outline, color: p.danger, size: 18),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(errorText, style: TextStyle(color: p.danger, fontSize: 13)),
                    ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 16),
            if (widget.askUsername) ...[
              FieldLabel(context.tr('host.username')),
              TextField(controller: _user, autofocus: _user.text.isEmpty),
              const SizedBox(height: 12),
            ],
            FieldLabel(context.tr(widget.passphrase ? 'ssh.passphrase' : 'host.password')),
            TextField(
              controller: _ctrl,
              autofocus: !widget.askUsername || _user.text.isNotEmpty,
              obscureText: _obscure,
              onSubmitted: (_) => _submit(),
              decoration: InputDecoration(
                suffixIcon: IconButton(
                  icon: Icon(_obscure ? Icons.visibility : Icons.visibility_off, size: 18),
                  onPressed: () => setState(() => _obscure = !_obscure),
                ),
              ),
            ),
            if (!widget.passphrase)
              CheckLabel(
                value: _remember,
                onChanged: (v) => setState(() => _remember = v),
                label: context.tr('host.remember_password'),
              ),
          ],
        ),
      ),
      actions: [
        OutlinedButton(onPressed: () => Navigator.pop(context), child: Text(context.tr('common.cancel'))),
        FilledButton(onPressed: _submit, child: Text(context.tr('ssh.connect'))),
      ],
    );
  }
}

/// 指纹显示框（主机身份核验）
class _FingerprintBox extends StatelessWidget {
  const _FingerprintBox({required this.label, required this.value, this.highlight = false});

  final String label;
  final String value;
  final bool highlight;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: p.input,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: highlight ? p.warning.withValues(alpha: 0.6) : p.borderStrong),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: TextStyle(fontSize: 12, color: p.textMuted)),
          const SizedBox(height: 4),
          SelectableText(
            value,
            style: TextStyle(fontFamily: 'monospace', fontSize: 13, color: p.text),
          ),
        ],
      ),
    );
  }
}
