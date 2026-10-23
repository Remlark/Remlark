import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../../app/app_services.dart';
import '../../../l10n/app_localizations.dart';
import '../../../ui_kit/check_label.dart';
import '../../../ui_kit/panel.dart';
import '../../keys/key_model.dart';
import '../../keys/ui/key_dialogs.dart';
import '../host_model.dart';
import '../hosts_controller.dart';
import 'host_form.dart';
import 'jump_host_picker_dialog.dart';
import '../../../ui_kit/app_menu.dart';

/// 编辑分区标题
class SectionTitle extends StatelessWidget {
  const SectionTitle(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 22, bottom: 12),
    child: Text(
      text,
      style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: Theme.of(context).colorScheme.onSurface),
    ),
  );
}

/// 密码输入 + 下方“记住密码”选项
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
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        LabeledField(
          label: context.tr('host.password'),
          child: TextField(
            controller: f.password,
            obscureText: _obscure,
            decoration: InputDecoration(
              suffixIcon: IconButton(
                icon: Icon(_obscure ? Icons.visibility : Icons.visibility_off, size: 18),
                onPressed: () => setState(() => _obscure = !_obscure),
              ),
            ),
          ),
        ),
        const SizedBox(height: 6),
        CheckLabel(
          value: f.savePassword,
          onChanged: (v) => f.update(() => f.savePassword = v),
          label: context.tr('host.remember_password'),
          helper: context.tr('host.password.helper'),
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
        if (f.authType == AuthType.key) FieldLabel(context.tr('auth.key.select')),
        if (f.authType == AuthType.key)
          Row(
            children: [
              Expanded(
                child: AppDropdown<String>(
                  value: f.keyUuid,
                  items: [for (final k in _keys) AppMenuItem(value: k.uuid, label: '${k.name}  (${k.keyType})')],
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
          TextButton.icon(
            icon: const Icon(Icons.add, size: 16),
            label: Text(context.tr('host.jump.add')),
            onPressed: () async {
              final uuid = await JumpHostPickerDialog.show(
                context,
                candidates: candidates,
                groups: hosts.groups,
              );
              if (!context.mounted || uuid == null) return;
              // 确认时再次校验，避免弹窗期间候选被删除或重复加入。
              if (hosts.sshHosts.any((h) => h.uuid == uuid) &&
                  !f.jumpChain.contains(uuid)) {
                f.update(() => f.jumpChain.add(uuid));
              }
            },
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
      crossAxisAlignment: CrossAxisAlignment.start,
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
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                flex: 3,
                child: LabeledField(
                  label: context.tr('proxy.host'),
                  child: TextField(controller: f.proxyHost),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: LabeledField(
                  label: context.tr('host.port'),
                  child: TextField(
                    controller: f.proxyPort,
                    keyboardType: TextInputType.number,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: LabeledField(
                  label: context.tr('proxy.user'),
                  child: TextField(controller: f.proxyUser),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: LabeledField(
                  label: context.tr('proxy.password'),
                  child: TextField(controller: f.proxyPass, obscureText: true),
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
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        PasswordFields(form: f),
        const SizedBox(height: 14),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: LabeledField(
                label: context.tr('rdp.domain'),
                child: TextField(controller: f.domain),
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: LabeledField(
                label: '${context.tr('rdp.width')} × ${context.tr('rdp.height')}',
                helper: context.tr('rdp.resolution.helper'),
                child: Row(
                  children: [
                    Expanded(
                      child: TextField(controller: f.width, inputFormatters: [FilteringTextInputFormatter.digitsOnly]),
                    ),
                    const Padding(padding: EdgeInsets.symmetric(horizontal: 8), child: Text('×')),
                    Expanded(
                      child: TextField(controller: f.height, inputFormatters: [FilteringTextInputFormatter.digitsOnly]),
                    ),
                  ],
                ),
              ),
            ),
          ],
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

/// VNC 凭据及可选 SSH：开启后显示 SSH 参数并提供独立终端入口。
class VncSection extends StatelessWidget {
  const VncSection({super.key, required this.form});
  final HostForm form;

  /// 显示共用密码及单协议能力说明。
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      PasswordFields(form: form),
      SwitchListTile(
        key: const ValueKey('vnc-enable-ssh'),
        contentPadding: EdgeInsets.zero,
        title: Text(context.tr('vnc.ssh.enable')),
        subtitle: Text(context.tr(form.vncSsh.enabled ? 'host.connections.shared' : 'vnc.only.helper')),
        value: form.vncSsh.enabled,
        onChanged: form.setSshEnabled,
      ),
      if (form.vncSsh.enabled) HostSshSection(form: form),
      if (form.preserveLegacySsh && !form.vncSsh.enabled) FieldHelper(context.tr('vnc.ssh.legacy')),
    ],
  );
}

/// 双协议主机的独立 SSH 配置分区：终端和文件传输共用。
class HostSshSection extends StatefulWidget {
  const HostSshSection({super.key, required this.form});

  final HostForm form;

  @override
  State<HostSshSection> createState() => _HostSshSectionState();
}

class _HostSshSectionState extends State<HostSshSection> {
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
    final ssh = f.vncSsh;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (ssh.enabled) ...[
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: 120,
                child: LabeledField(
                  label: context.tr('vnc.ssh.port'),
                  child: TextField(
                    controller: f.sshPort,
                    keyboardType: TextInputType.number,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  ),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: LabeledField(
                  label: context.tr('vnc.ssh.auth'),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: AppDropdown<AuthType>(
                      value: ssh.authType,
                      items: [
                        for (final type in AuthType.values) AppMenuItem(value: type, label: context.tr('auth.${type.name}')),
                      ],
                      onChanged: (v) {
                        if (v != null) f.update(() => f.vncSsh = ssh.copyWith(authType: v));
                      },
                    ),
                  ),
                ),
              ),
            ],
          ),
          if (ssh.authType == AuthType.key) ...[
            const SizedBox(height: 14),
            LabeledField(
              label: context.tr('auth.key.select'),
              child: AppDropdown<String>(
                value: ssh.keyUuid,
                items: [for (final k in _keys) AppMenuItem(value: k.uuid, label: '${k.name}  (${k.keyType})')],
                onChanged: (v) => f.update(() => f.vncSsh = ssh.copyWith(keyUuid: () => v)),
              ),
            ),
          ],
          SectionTitle(context.tr('host.section.jump')),
          JumpChainSection(form: f),
          SectionTitle(context.tr('host.section.proxy')),
          ProxySection(form: f),
        ],
      ],
    );
  }
}
