import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../../app/theme/app_palette.dart';
import '../../../l10n/app_localizations.dart';
import '../../../ui_kit/app_dialog.dart';
import '../../../ui_kit/app_menu.dart';
import '../../../ui_kit/nav_tile.dart';
import '../../../ui_kit/panel.dart';
import '../../../utils/ui_utils.dart';
import '../../../utils/os_registry.dart';
import '../../sync/sync_service.dart';
import '../host_model.dart';
import '../vnc_ssh_config.dart';
import '../hosts_controller.dart';
import 'host_editor_sections.dart';
import 'host_form.dart';
import 'host_connection_forms.dart';

/// 主机编辑对话框（新建 / 编辑），根据协议显示对应分区
class HostEditorDialog extends StatefulWidget {
  const HostEditorDialog({
    super.key,
    this.existing,
    required this.protocol,
    this.groupUuid,
  });

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
      builder: (_) => HostEditorDialog(
        existing: existing,
        protocol: protocol,
        groupUuid: groupUuid,
      ),
    );
  }

  @override
  State<HostEditorDialog> createState() => _HostEditorDialogState();
}

class _HostEditorDialogState extends State<HostEditorDialog> {
  late final HostConnectionForms _connections = HostConnectionForms(
    widget.existing,
    widget.protocol,
    widget.groupUuid,
  );
  HostForm get _form => _connections.current;

  /// 兼容旧版 VNC 关联独立 SSH 主机的配置。
  void _migrateLegacySsh() {
    final vnc = _connections.forms[HostProtocol.vnc]!;
    vnc.migrateLegacySsh(
      widget.existing?.legacyTransferHost == null
          ? null
          : context.read<HostsController>().byUuid(
              widget.existing!.legacyTransferHost!,
            ),
    );
    if (vnc.vncSsh.enabled &&
        !_connections.enabled.contains(HostProtocol.ssh)) {
      final ssh = _connections.forms[HostProtocol.ssh]!;
      ssh.port.text = vnc.sshPort.text;
      ssh.username.text = vnc.username.text;
      ssh.password.text = vnc.password.text;
      ssh.authType = vnc.vncSsh.authType;
      ssh.keyUuid = vnc.vncSsh.keyUuid;
      _connections.enabled.add(HostProtocol.ssh);
    }
  }

  final _scroll = ScrollController();
  final Map<String, GlobalKey> _keys = {};
  bool _saving = false;
  String? _current;

  @override
  void initState() {
    super.initState();
    _migrateLegacySsh();
    _scroll.addListener(_onScroll);
  }

  @override
  void dispose() {
    _connections.dispose();
    _scroll.dispose();
    super.dispose();
  }

  GlobalKey _key(String id) => _keys.putIfAbsent(id, GlobalKey.new);

  /// 当前协议的分区：(id, 图标, 标题)
  List<(String, IconData, String)> _sections(BuildContext context) => [
    ('basic', Icons.description_outlined, context.tr('host.section.basic')),
    if (_form.protocol == HostProtocol.ssh) ...[
      ('auth', Icons.shield_outlined, context.tr('host.section.auth')),
      ('jump', Icons.hub_outlined, context.tr('host.section.jump_proxy')),
    ],
    if (_form.protocol == HostProtocol.rdp) ...[
      ('rdp', Icons.desktop_windows_outlined, context.tr('host.section.rdp')),
      ('proxy', Icons.hub_outlined, context.tr('host.section.proxy')),
    ],
    if (_form.protocol == HostProtocol.vnc)
      ('vnc', Icons.desktop_windows_outlined, context.tr('host.section.vnc')),
    (
      'other',
      Icons.sticky_note_2_outlined,
      context.tr('host.section.note_sync'),
    ),
  ];

  /// 点击分区导航：滚动到对应分区
  void _jump(String id) {
    final ctx = _keys[id]?.currentContext;
    setState(() => _current = id);
    if (ctx != null)
      Scrollable.ensureVisible(
        ctx,
        duration: const Duration(milliseconds: 220),
        alignment: 0,
      );
  }

  /// 滚动时高亮视口顶部所在的分区
  void _onScroll() {
    String? found;
    for (final e in _keys.entries) {
      final box = e.value.currentContext?.findRenderObject() as RenderBox?;
      final viewport =
          _scroll.position.context.storageContext.findRenderObject()
              as RenderBox?;
      if (box == null || viewport == null || !box.attached) continue;
      final dy = box.localToGlobal(Offset.zero, ancestor: viewport).dy;
      if (dy <= 40) found = e.key;
    }
    if (_scroll.position.pixels >= _scroll.position.maxScrollExtent - 4 &&
        _keys.isNotEmpty)
      found = 'other';
    if (found != null && found != _current) setState(() => _current = found);
  }

  /// 校验后保存配置及同步状态。
  Future<void> _save() async {
    final error = _connections.validate();
    if (error != null) {
      UiUtils.toast(context.tr(error), error: true);
      return;
    }
    setState(() => _saving = true);
    final hosts = context.read<HostsController>();
    final sync = context.read<SyncService>();
    try {
      final saved = await hosts.saveHost(_connections.build());
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
    final p = context.palette;
    final groups = context.read<HostsController>().groups;
    return ListenableBuilder(
      listenable: Listenable.merge(_connections.forms.values.toList()),
      builder: (context, _) {
        final f = _form;
        final sections = _sections(context);
        final current = sections.any((e) => e.$1 == _current)
            ? _current
            : sections.first.$1;
        return AppDialog(
          title: context.tr(widget.existing == null ? 'host.new' : 'host.edit'),
          width: 880,
          scrollable: false,
          contentPadding: EdgeInsets.zero,
          headerExtra: SegmentedButton<HostProtocol>(
            showSelectedIcon: false,
            multiSelectionEnabled: true,
            style: const ButtonStyle(
              minimumSize: WidgetStatePropertyAll(Size(0, 36)),
            ),
            segments: const [
              ButtonSegment(value: HostProtocol.ssh, label: Text('SSH')),
              ButtonSegment(value: HostProtocol.vnc, label: Text('VNC')),
              ButtonSegment(value: HostProtocol.rdp, label: Text('RDP')),
            ],
            selected: _connections.enabled,
            // 点击协议开关后直接进入该协议的配置；至少保留一种连接。
            onSelectionChanged: (s) {
              if (s.isEmpty) return;
              final added = s.difference(_connections.enabled);
              _connections.enabled
                ..clear()
                ..addAll(s);
              _connections.select(added.isNotEmpty ? added.first : s.first);
              setState(() {});
            },
          ),
          content: SizedBox(
            height: 520,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Container(
                  width: 190,
                  padding: const EdgeInsets.fromLTRB(10, 4, 10, 10),
                  decoration: BoxDecoration(
                    border: Border(
                      top: BorderSide(color: p.border),
                      right: BorderSide(color: p.border),
                    ),
                  ),
                  child: ListView(
                    padding: const EdgeInsets.only(top: 8),
                    children: [
                      for (final protocol in HostProtocol.values)
                        if (_connections.enabled.contains(protocol))
                          Padding(
                            padding: const EdgeInsets.only(bottom: 4),
                            child: NavTile(
                              icon: switch (protocol) {
                                HostProtocol.ssh => Icons.terminal_rounded,
                                HostProtocol.vnc =>
                                  Icons.desktop_windows_outlined,
                                HostProtocol.rdp => Icons.window_outlined,
                              },
                              label: protocol.name.toUpperCase(),
                              selected: _connections.active == protocol,
                              onTap: () =>
                                  setState(() => _connections.select(protocol)),
                            ),
                          ),
                      const Divider(),
                      for (final (id, icon, label) in sections)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 4),
                          child: NavTile(
                            icon: icon,
                            label: label,
                            selected: current == id,
                            onTap: () => _jump(id),
                          ),
                        ),
                    ],
                  ),
                ),
                Expanded(
                  child: Container(
                    decoration: BoxDecoration(
                      border: Border(top: BorderSide(color: p.border)),
                    ),
                    child: SingleChildScrollView(
                      controller: _scroll,
                      padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          KeyedSubtree(
                            key: _key('basic'),
                            child: SectionTitle(
                              context.tr('host.section.basic'),
                            ),
                          ),
                          _basic(context, f, groups),
                          if (f.protocol == HostProtocol.ssh) ...[
                            KeyedSubtree(
                              key: _key('auth'),
                              child: SectionTitle(
                                context.tr('host.section.auth'),
                              ),
                            ),
                            SshAuthSection(form: f),
                            KeyedSubtree(
                              key: _key('jump'),
                              child: SectionTitle(
                                context.tr('host.section.jump'),
                              ),
                            ),
                            JumpChainSection(form: f),
                            SectionTitle(context.tr('host.section.proxy')),
                            ProxySection(form: f),
                          ],
                          if (f.protocol == HostProtocol.rdp) ...[
                            KeyedSubtree(
                              key: _key('rdp'),
                              child: SectionTitle(
                                context.tr('host.section.rdp'),
                              ),
                            ),
                            RdpSection(form: f),
                            KeyedSubtree(
                              key: _key('proxy'),
                              child: SectionTitle(
                                context.tr('host.section.proxy'),
                              ),
                            ),
                            ProxySection(form: f),
                          ],
                          if (f.protocol == HostProtocol.vnc) ...[
                            KeyedSubtree(
                              key: _key('vnc'),
                              child: SectionTitle(
                                context.tr('host.section.vnc'),
                              ),
                            ),
                            VncSection(form: f, showSshConfig: false),
                          ],
                          KeyedSubtree(
                            key: _key('other'),
                            child: SectionTitle(
                              context.tr('host.section.note_sync'),
                            ),
                          ),
                          FieldLabel(context.tr('host.note')),
                          TextField(controller: f.note, maxLines: 3),
                          const SizedBox(height: 8),
                          SwitchListTile(
                            contentPadding: EdgeInsets.zero,
                            value: f.syncEnabled,
                            onChanged: (v) => f.update(() => f.syncEnabled = v),
                            title: Text(
                              context.tr('host.sync'),
                              style: const TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            subtitle: Text(
                              context.tr('host.sync.helper'),
                              style: TextStyle(
                                fontSize: 13,
                                color: p.textMuted,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            OutlinedButton(
              onPressed: () => Navigator.pop(context),
              child: Text(context.tr('common.cancel')),
            ),
            FilledButton(
              onPressed: _saving ? null : _save,
              child: Text(
                context.tr(
                  widget.existing == null ? 'host.create' : 'host.save',
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  /// 基本信息：名称、分组、地址、端口、用户名（VNC 可使用系统账户）
  Widget _basic(BuildContext context, HostForm f, List<GroupEntry> groups) {
    Widget field(String label, Widget input, {bool required = false}) =>
        LabeledField(label: label, required: required, child: input);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: field(
                context.tr('host.name'),
                TextField(controller: f.name, autofocus: true),
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: field(
                context.tr('group.title'),
                AppDropdown<String?>(
                  // 分组已被删除时按“无分组”显示
                  value: groups.any((g) => g.uuid == f.groupUuid)
                      ? f.groupUuid
                      : null,
                  items: [
                    AppMenuItem(value: null, label: context.tr('group.none')),
                    for (final g in groups)
                      AppMenuItem(value: g.uuid, label: g.name),
                  ],
                  onChanged: (v) => f.update(() => f.groupUuid = v),
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
              flex: 3,
              child: field(
                context.tr('host.address'),
                TextField(controller: f.address),
                required: true,
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              flex: 2,
              child: field(
                f.protocol == HostProtocol.vnc
                    ? context.tr('vnc.port')
                    : context.tr('host.port'),
                TextField(
                  controller: f.port,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                ),
                required: true,
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
                label: context.tr('host.username'),
                // VNC：macOS 屏幕共享使用系统账户认证需要用户名，标准 VNC 只需密码。
                helper: f.protocol == HostProtocol.vnc
                    ? context.tr('vnc.username.helper')
                    : null,
                child: TextField(controller: f.username),
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: LabeledField(
                label: context.tr('host.operating_system'),
                child: AppDropdown<String?>(
                  value: _connections.osOverride,
                  items: [
                    AppMenuItem(
                      value: null,
                      label: context.tr('host.operating_system.auto'),
                    ),
                    for (final id in OsRegistry.ids.toList()..sort())
                      AppMenuItem(value: id, label: OsRegistry.displayName(id)),
                  ],
                  onChanged: (id) =>
                      setState(() => _connections.osOverride = id),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}
