import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../app/theme/app_palette.dart';
import '../../../l10n/app_localizations.dart';
import '../../../ui_kit/app_dialog.dart';
import '../../../ui_kit/panel.dart';
import '../../../utils/id_utils.dart';
import '../proxies_controller.dart';
import '../proxy_profile.dart';
import '../../hosts/host_model.dart';
import '../proxy_connection_test.dart';
import 'proxy_connection_test_section.dart';

/// 代理新增和编辑弹窗，保存成功后才关闭。
class ProxyEditorDialog extends StatefulWidget {
  const ProxyEditorDialog({
    super.key,
    required this.controller,
    this.existing,
    this.connectionTest,
  });

  final ProxiesController controller;
  final ProxyEntry? existing;
  final ProxyConnectionTest? connectionTest;

  /// 在当前窗口内打开编辑，不丢失外层主机表单。
  static Future<void> show(
    BuildContext context,
    ProxiesController controller, [
    ProxyEntry? entry,
  ]) => showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (_) => ProxyEditorDialog(controller: controller, existing: entry),
  );

  /// 创建输入及验证状态。
  @override
  State<ProxyEditorDialog> createState() => _ProxyEditorDialogState();
}

class _ProxyEditorDialogState extends State<ProxyEditorDialog> {
  final _form = GlobalKey<FormState>();
  late final _uuid = widget.existing?.uuid ?? IdUtils.newId();
  late final _name = TextEditingController(text: widget.existing?.name ?? '');
  late final _host = TextEditingController(
    text: widget.existing?.config.host ?? '',
  );
  late final _port = TextEditingController(
    text: '${widget.existing?.config.port ?? 1080}',
  );
  late final _user = TextEditingController(
    text: widget.existing?.config.username ?? '',
  );
  late final _password = TextEditingController(
    text: widget.existing?.config.password ?? '',
  );
  late ProxyType _type = widget.existing?.config.type ?? ProxyType.socks5;
  bool _obscure = true;
  bool _saving = false;
  String? _error;

  /// 连接参数变化时刷新检测区域，名称变化不会使检测失效。
  @override
  void initState() {
    super.initState();
    for (final controller in [_host, _port, _user, _password]) {
      controller.addListener(_connectionChanged);
    }
  }

  /// 输入时把最新参数传给测试区。
  void _connectionChanged() => setState(() {});

  /// 生成当前输入的连接快照，供保存和检测复用。
  ProxyConfig get _config => ProxyConfig(
    type: _type,
    host: _host.text.trim(),
    port: int.tryParse(_port.text) ?? 0,
    username: _user.text.trim(),
    password: _password.text.isEmpty ? null : _password.text,
  );

  /// 释放所有凭据输入控制器。
  @override
  void dispose() {
    for (final controller in [_name, _host, _port, _user, _password]) {
      controller.dispose();
    }
    super.dispose();
  }

  /// 校验后保存；错误留在当前表单，便于修正并重试。
  Future<void> _save() async {
    if (_saving || !_form.currentState!.validate()) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await widget.controller.save(
        ProxyEntry(uuid: _uuid, name: _name.text.trim(), config: _config),
      );
      if (mounted) Navigator.pop(context);
    } catch (_) {
      if (mounted) {
        setState(() {
          _saving = false;
          _error = context.tr('proxy.save_failed');
        });
      }
    }
  }

  /// 名称和地址必填，地址仅接受主机名或 IP，不接受含协议头的 URL。
  String? _required(String? value) => value == null || value.trim().isEmpty
      ? context.tr('proxy.required')
      : null;

  /// 表单采用设计稿的紧凑两列表达，认证区域使用可选说明。
  @override
  Widget build(BuildContext context) {
    final usage = widget.controller.usage[widget.existing?.uuid] ?? 0;
    return PopScope(
      canPop: !_saving,
      child: AppDialog(
        title: context.tr(widget.existing == null ? 'proxy.add' : 'proxy.edit'),
        subtitle: context.tr('proxy.effect'),
        width: 600,
        content: Form(
          key: _form,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              LabeledField(
                label: context.tr('proxy.name'),
                required: true,
                child: TextFormField(
                  key: const ValueKey('proxy-name'),
                  controller: _name,
                  autofocus: true,
                  validator: _required,
                ),
              ),
              const SizedBox(height: 16),
              LabeledField(
                label: context.tr('proxy.protocol'),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: SizedBox(
                    width: 270,
                    child: SegmentedButton<ProxyType>(
                      showSelectedIcon: false,
                      segments: const [
                        ButtonSegment(
                          value: ProxyType.http,
                          label: Text('HTTP'),
                        ),
                        ButtonSegment(
                          value: ProxyType.socks5,
                          label: Text('SOCKS5'),
                        ),
                      ],
                      selected: {_type},
                      onSelectionChanged: _saving
                          ? null
                          : (selection) =>
                                setState(() => _type = selection.first),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    flex: 3,
                    child: LabeledField(
                      label: context.tr('proxy.host'),
                      required: true,
                      child: TextFormField(
                        key: const ValueKey('proxy-host'),
                        controller: _host,
                        validator: (value) {
                          final required = _required(value);
                          if (required != null) return required;
                          return RegExp(r'\s|://|/').hasMatch(value!.trim())
                              ? context.tr('proxy.host_invalid')
                              : null;
                        },
                      ),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: LabeledField(
                      label: context.tr('host.port'),
                      required: true,
                      child: TextFormField(
                        key: const ValueKey('proxy-port'),
                        controller: _port,
                        keyboardType: TextInputType.number,
                        inputFormatters: [
                          FilteringTextInputFormatter.digitsOnly,
                        ],
                        validator: (value) {
                          final port = int.tryParse(value ?? '');
                          return port == null || port < 1 || port > 65535
                              ? context.tr('host.port.invalid')
                              : null;
                        },
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              const Divider(),
              const SizedBox(height: 16),
              Text(
                context.tr('proxy.auth_optional'),
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 12),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: LabeledField(
                      label: context.tr('host.username'),
                      child: TextFormField(
                        key: const ValueKey('proxy-user'),
                        controller: _user,
                      ),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: LabeledField(
                      label: context.tr('host.password'),
                      child: TextFormField(
                        key: const ValueKey('proxy-password'),
                        controller: _password,
                        obscureText: _obscure,
                        decoration: InputDecoration(
                          suffixIcon: IconButton(
                            tooltip: context.tr(
                              _obscure
                                  ? 'proxy.show_password'
                                  : 'proxy.hide_password',
                            ),
                            icon: Icon(
                              _obscure
                                  ? Icons.visibility_outlined
                                  : Icons.visibility_off_outlined,
                              size: 18,
                            ),
                            onPressed: () =>
                                setState(() => _obscure = !_obscure),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              const Divider(),
              const SizedBox(height: 16),
              ProxyConnectionTestSection(
                config: _config,
                enabled: !_saving,
                connectionTest: widget.connectionTest,
              ),
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: Text(
                    _error!,
                    style: TextStyle(color: context.palette.danger),
                  ),
                ),
            ],
          ),
        ),
        actions: [
          Expanded(
            child: Text(
              context.tr(usage > 0 ? 'proxy.usage' : 'proxy.unused', {
                'count': usage,
              }),
              style: TextStyle(fontSize: 12, color: context.palette.textMuted),
            ),
          ),
          OutlinedButton(
            onPressed: _saving ? null : () => Navigator.pop(context),
            child: Text(context.tr('common.cancel')),
          ),
          FilledButton(
            onPressed: _saving ? null : _save,
            child: Text(context.tr('common.save')),
          ),
        ],
      ),
    );
  }
}
