import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../../l10n/app_localizations.dart';
import '../../../utils/ui_utils.dart';
import '../../sync/sync_service.dart';
import '../host_model.dart';
import '../hosts_controller.dart';
import 'host_editor_sections.dart';
import 'host_form.dart';

/// 主机编辑对话框（新建 / 编辑），根据协议显示对应分区
class HostEditorDialog extends StatefulWidget {
  const HostEditorDialog({super.key, this.existing, required this.protocol, this.groupUuid});

  final HostEntry? existing;
  final HostProtocol protocol;
  final String? groupUuid;

  /// 打开编辑对话框
  static Future<void> show(
    BuildContext context, {
    HostEntry? existing,
    HostProtocol protocol = HostProtocol.ssh,
    String? groupUuid,
  }) {
    return showDialog(
      context: context,
      builder: (_) => HostEditorDialog(existing: existing, protocol: protocol, groupUuid: groupUuid),
    );
  }

  @override
  State<HostEditorDialog> createState() => _HostEditorDialogState();
}

class _HostEditorDialogState extends State<HostEditorDialog> {
  late final HostForm _form = HostForm(widget.existing, widget.protocol, widget.groupUuid);
  bool _saving = false;

  @override
  void dispose() {
    _form.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_form.address.text.trim().isEmpty) {
      UiUtils.toast(context.tr('host.address.required'), error: true);
      return;
    }
    setState(() => _saving = true);
    final hosts = context.read<HostsController>();
    final sync = context.read<SyncService>();
    try {
      final saved = await hosts.saveHost(_form.build());
      final wasSync = widget.existing?.syncEnabled ?? false;
      if (_form.syncEnabled && !wasSync) {
        await sync.enable(saved);
      } else if (!_form.syncEnabled && wasSync) {
        await sync.removeFromServer(saved.uuid);
      }
      if (mounted) Navigator.pop(context);
    } catch (e) {
      UiUtils.toast('$e', error: true);
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final groups = context.read<HostsController>().groups;
    return AlertDialog(
      title: Text(context.tr(widget.existing == null ? 'host.new' : 'host.edit')),
      content: SizedBox(
        width: 640,
        height: 560,
        child: ListenableBuilder(
          listenable: _form,
          builder: (context, _) {
            final f = _form;
            return SingleChildScrollView(
              padding: const EdgeInsets.only(right: 12, top: 6),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SegmentedButton<HostProtocol>(
                    segments: const [
                      ButtonSegment(value: HostProtocol.ssh, label: Text('SSH')),
                      ButtonSegment(value: HostProtocol.rdp, label: Text('RDP')),
                      ButtonSegment(value: HostProtocol.vnc, label: Text('VNC')),
                    ],
                    selected: {f.protocol},
                    onSelectionChanged: widget.existing == null ? (s) => f.setProtocol(s.first) : null,
                  ),
                  SectionTitle(context.tr('host.section.basic')),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: f.name,
                          autofocus: true,
                          decoration: InputDecoration(labelText: context.tr('host.name')),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: DropdownButtonFormField<String?>(
                          isExpanded: true,
                          initialValue: groups.any((g) => g.uuid == f.groupUuid) ? f.groupUuid : null,
                          decoration: InputDecoration(labelText: context.tr('group.title')),
                          items: [
                            DropdownMenuItem(
                              value: null,
                              child: Text(context.tr('group.none'), overflow: TextOverflow.ellipsis),
                            ),
                            for (final g in groups)
                              DropdownMenuItem(
                                value: g.uuid,
                                child: Text(g.name, overflow: TextOverflow.ellipsis),
                              ),
                          ],
                          onChanged: (v) => f.update(() => f.groupUuid = v),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        flex: 3,
                        child: TextField(
                          controller: f.address,
                          decoration: InputDecoration(labelText: context.tr('host.address')),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: TextField(
                          controller: f.port,
                          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                          decoration: InputDecoration(labelText: context.tr('host.port')),
                        ),
                      ),
                    ],
                  ),
                  if (f.protocol != HostProtocol.vnc) ...[
                    const SizedBox(height: 12),
                    TextField(
                      controller: f.username,
                      decoration: InputDecoration(labelText: context.tr('host.username')),
                    ),
                  ],
                  if (f.protocol == HostProtocol.ssh) ...[
                    SectionTitle(context.tr('host.section.auth')),
                    SshAuthSection(form: f),
                    SectionTitle(context.tr('host.section.jump')),
                    JumpChainSection(form: f),
                    SectionTitle(context.tr('host.section.proxy')),
                    ProxySection(form: f),
                  ],
                  if (f.protocol == HostProtocol.rdp) ...[
                    SectionTitle(context.tr('host.section.rdp')),
                    RdpSection(form: f),
                    SectionTitle(context.tr('host.section.proxy')),
                    ProxySection(form: f),
                  ],
                  if (f.protocol == HostProtocol.vnc) ...[
                    SectionTitle(context.tr('host.section.vnc')),
                    VncSection(form: f),
                  ],
                  SectionTitle(context.tr('host.section.other')),
                  TextField(
                    controller: f.note,
                    maxLines: 2,
                    decoration: InputDecoration(labelText: context.tr('host.note')),
                  ),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    value: f.syncEnabled,
                    onChanged: (v) => f.update(() => f.syncEnabled = v),
                    title: Text(context.tr('host.sync')),
                    subtitle: Text(context.tr('host.sync.helper')),
                  ),
                ],
              ),
            );
          },
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: Text(context.tr('common.cancel'))),
        FilledButton(onPressed: _saving ? null : _save, child: Text(context.tr('common.save'))),
      ],
    );
  }
}
