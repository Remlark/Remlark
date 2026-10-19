import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../../app/app_services.dart';
import '../../../l10n/app_localizations.dart';
import '../../keys/key_model.dart';
import '../../keys/ui/key_dialogs.dart';
import '../host_model.dart';
import '../hosts_controller.dart';
import 'host_form.dart';

/// 编辑分区标题
class SectionTitle extends StatelessWidget {
  const SectionTitle(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 18, bottom: 10),
    child: Text(
      text,
      style: Theme.of(context).textTheme.titleSmall
          ?.copyWith(color: Theme.of(context).colorScheme.primary, fontWeight: FontWeight.w600),
    ),
  );
}

/// 密码输入 + 记住密码
class PasswordFields extends StatefulWidget {
  const PasswordFields({super.key, required this.form});

  final HostForm form;

  @override
  State<PasswordFields> createState() => _PasswordFieldsState();
}

class _PasswordFieldsState extends State<PasswordFields> {
  bool _obscure = true;

  @override
  Widget build(BuildContext context) {
    final f = widget.form;
    return Row(
      children: [
        Expanded(
          child: TextField(
            controller: f.password,
            obscureText: _obscure,
            decoration: InputDecoration(
              labelText: context.tr('host.password'),
              helperText: context.tr('host.password.helper'),
              suffixIcon: IconButton(
                icon: Icon(_obscure ? Icons.visibility : Icons.visibility_off, size: 18),
                onPressed: () => setState(() => _obscure = !_obscure),
              ),
            ),
          ),
        ),
        const SizedBox(width: 12),
        SizedBox(
          width: 160,
          child: CheckboxListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            controlAffinity: ListTileControlAffinity.leading,
            value: f.savePassword,
            onChanged: (v) => f.update(() => f.savePassword = v ?? false),
            title: Text(context.tr('host.remember_password')),
          ),
        ),
      ],
    );
  }
}

/// SSH 认证分区：密码 / 密钥 / 键盘交互
class SshAuthSection extends StatefulWidget {
  const SshAuthSection({super.key, required this.form});

  final HostForm form;

  @override
  State<SshAuthSection> createState() => _SshAuthSectionState();
}

class _SshAuthSectionState extends State<SshAuthSection> {
  List<KeyEntry> _keys = [];

  @override
  void initState() {
    super.initState();
    _loadKeys();
  }

  Future<void> _loadKeys() async {
    final keys = await context.read<AppServices>().keyRepo.list();
    if (mounted) setState(() => _keys = keys);
  }

  @override
  Widget build(BuildContext context) {
    final f = widget.form;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SegmentedButton<AuthType>(
          segments: [
            ButtonSegment(
              value: AuthType.password,
              label: Text(context.tr('auth.password')),
              icon: const Icon(Icons.password, size: 16),
            ),
            ButtonSegment(
              value: AuthType.key,
              label: Text(context.tr('auth.key')),
              icon: const Icon(Icons.key, size: 16),
            ),
            ButtonSegment(
              value: AuthType.keyboard,
              label: Text(context.tr('auth.keyboard')),
              icon: const Icon(Icons.keyboard, size: 16),
            ),
          ],
          selected: {f.authType},
          onSelectionChanged: (s) => f.update(() => f.authType = s.first),
        ),
        const SizedBox(height: 14),
        if (f.authType != AuthType.key) PasswordFields(form: f),
        if (f.authType == AuthType.key)
          Row(
            children: [
              Expanded(
                child: DropdownButtonFormField<String>(
                  initialValue: _keys.any((k) => k.uuid == f.keyUuid) ? f.keyUuid : null,
                  decoration: InputDecoration(labelText: context.tr('auth.key.select')),
                  items: [
                    for (final k in _keys) DropdownMenuItem(value: k.uuid, child: Text('${k.name}  (${k.keyType})')),
                  ],
                  onChanged: (v) => f.update(() => f.keyUuid = v),
                ),
              ),
              const SizedBox(width: 8),
              OutlinedButton.icon(
                icon: const Icon(Icons.auto_fix_high, size: 16),
                label: Text(context.tr('key.generate')),
                onPressed: () async {
                  final k = await KeyDialogs.generate(context);
                  if (k != null) {
                    await _loadKeys();
                    f.update(() => f.keyUuid = k.uuid);
                  }
                },
              ),
              const SizedBox(width: 8),
              OutlinedButton.icon(
                icon: const Icon(Icons.file_open_outlined, size: 16),
                label: Text(context.tr('key.import')),
                onPressed: () async {
                  final k = await KeyDialogs.import(context);
                  if (k != null) {
                    await _loadKeys();
                    f.update(() => f.keyUuid = k.uuid);
                  }
                },
              ),
            ],
          ),
        if (f.authType == AuthType.key && f.keyUuid != null)
          Builder(
            builder: (context) {
              final k = _keys.where((k) => k.uuid == f.keyUuid).firstOrNull;
              if (k == null) return const SizedBox.shrink();
              return Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        k.publicKey,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontFamily: 'monospace', fontSize: 11),
                      ),
                    ),
                    TextButton.icon(
                      icon: const Icon(Icons.copy, size: 14),
                      label: Text(context.tr('key.copy_public')),
                      onPressed: () => Clipboard.setData(ClipboardData(text: k.publicKey)),
                    ),
                  ],
                ),
              );
            },
          ),
      ],
    );
  }
}

/// 跳板链分区：按顺序添加、调整、移除中间服务器
class JumpChainSection extends StatelessWidget {
  const JumpChainSection({super.key, required this.form});

  final HostForm form;

  @override
  Widget build(BuildContext context) {
    final f = form;
    final hosts = context.read<HostsController>();
    final candidates = hosts.sshHosts
        .where((h) => h.uuid != f.existing?.uuid && !f.jumpChain.contains(h.uuid))
        .toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (f.jumpChain.isEmpty) Text(context.tr('host.jump.empty'), style: Theme.of(context).textTheme.bodySmall),
        for (var i = 0; i < f.jumpChain.length; i++)
          Builder(
            builder: (context) {
              final h = hosts.byUuid(f.jumpChain[i]);
              return ListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                leading: CircleAvatar(radius: 12, child: Text('${i + 1}', style: const TextStyle(fontSize: 11))),
                title: Text(h?.name ?? f.jumpChain[i]),
                subtitle: Text(h?.endpoint ?? context.tr('host.jump.missing')),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      icon: const Icon(Icons.arrow_upward, size: 16),
                      onPressed: i == 0
                          ? null
                          : () => f.update(() {
                              final x = f.jumpChain.removeAt(i);
                              f.jumpChain.insert(i - 1, x);
                            }),
                    ),
                    IconButton(
                      icon: const Icon(Icons.arrow_downward, size: 16),
                      onPressed: i == f.jumpChain.length - 1
                          ? null
                          : () => f.update(() {
                              final x = f.jumpChain.removeAt(i);
                              f.jumpChain.insert(i + 1, x);
                            }),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close, size: 16),
                      onPressed: () => f.update(() => f.jumpChain.removeAt(i)),
                    ),
                  ],
                ),
              );
            },
          ),
        if (candidates.isNotEmpty)
          MenuAnchor(
            builder: (ctx, ctrl, _) => TextButton.icon(
              icon: const Icon(Icons.add, size: 16),
              label: Text(context.tr('host.jump.add')),
              onPressed: () => ctrl.isOpen ? ctrl.close() : ctrl.open(),
            ),
            menuChildren: [
              for (final h in candidates)
                MenuItemButton(
                  onPressed: () => f.update(() => f.jumpChain.add(h.uuid)),
                  child: Text('${h.name}  ${h.endpoint}'),
                ),
            ],
          ),
      ],
    );
  }
}

/// 出口代理分区
class ProxySection extends StatelessWidget {
  const ProxySection({super.key, required this.form});

  final HostForm form;

  @override
  Widget build(BuildContext context) {
    final f = form;
    return Column(
      children: [
        SegmentedButton<ProxyType>(
          segments: [
            ButtonSegment(value: ProxyType.none, label: Text(context.tr('proxy.none'))),
            const ButtonSegment(value: ProxyType.http, label: Text('HTTP')),
            const ButtonSegment(value: ProxyType.socks5, label: Text('SOCKS5')),
          ],
          selected: {f.proxyType},
          onSelectionChanged: (s) => f.update(() => f.proxyType = s.first),
        ),
        if (f.proxyType != ProxyType.none) ...[
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                flex: 3,
                child: TextField(
                  controller: f.proxyHost,
                  decoration: InputDecoration(labelText: context.tr('proxy.host')),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: TextField(
                  controller: f.proxyPort,
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  decoration: InputDecoration(labelText: context.tr('host.port')),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: f.proxyUser,
                  decoration: InputDecoration(labelText: context.tr('proxy.user')),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: TextField(
                  controller: f.proxyPass,
                  obscureText: true,
                  decoration: InputDecoration(labelText: context.tr('proxy.password')),
                ),
              ),
            ],
          ),
        ],
      ],
    );
  }
}

/// RDP 选项分区
class RdpSection extends StatelessWidget {
  const RdpSection({super.key, required this.form});

  final HostForm form;

  @override
  Widget build(BuildContext context) {
    final f = form;
    return Column(
      children: [
        PasswordFields(form: f),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: f.domain,
                decoration: InputDecoration(labelText: context.tr('rdp.domain')),
              ),
            ),
            const SizedBox(width: 12),
            SizedBox(
              width: 100,
              child: TextField(
                controller: f.width,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                decoration: InputDecoration(labelText: context.tr('rdp.width')),
              ),
            ),
            const Padding(padding: EdgeInsets.symmetric(horizontal: 6), child: Text('×')),
            SizedBox(
              width: 100,
              child: TextField(
                controller: f.height,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                decoration: InputDecoration(labelText: context.tr('rdp.height')),
              ),
            ),
          ],
        ),
        Align(
          alignment: Alignment.centerLeft,
          child: Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(context.tr('rdp.resolution.helper'), style: Theme.of(context).textTheme.bodySmall),
          ),
        ),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          value: f.clipboard,
          onChanged: (v) => f.update(() => f.clipboard = v),
          title: Text(context.tr('rdp.clipboard')),
          subtitle: Text(context.tr('rdp.clipboard.helper')),
        ),
      ],
    );
  }
}

/// VNC 选项分区：密码与文件传输（经关联 SSH 主机）
class VncSection extends StatelessWidget {
  const VncSection({super.key, required this.form});

  final HostForm form;

  @override
  Widget build(BuildContext context) {
    final f = form;
    final ssh = context.read<HostsController>().sshHosts;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        PasswordFields(form: f),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: DropdownButtonFormField<String?>(
                initialValue: ssh.any((h) => h.uuid == f.transferHost) ? f.transferHost : null,
                decoration: InputDecoration(
                  labelText: context.tr('vnc.transfer_host'),
                  helperText: context.tr('vnc.transfer_host.helper'),
                ),
                items: [
                  DropdownMenuItem(value: null, child: Text(context.tr('common.none'))),
                  for (final h in ssh) DropdownMenuItem(value: h.uuid, child: Text('${h.name}  ${h.endpoint}')),
                ],
                onChanged: (v) => f.update(() => f.transferHost = v),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: TextField(
                controller: f.transferDir,
                decoration: InputDecoration(labelText: context.tr('vnc.transfer_dir')),
              ),
            ),
          ],
        ),
      ],
    );
  }
}
