import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../l10n/app_localizations.dart';
import '../../../ui_kit/app_dialog.dart';
import '../../../utils/id_utils.dart';
import '../../ai/agent_config.dart';
import '../../ai/runtime/agent_runtime.dart';
import 'agent_runtime_status.dart';

/// 添加 / 编辑 Agent。选择需要本地运行环境的类型（如 DeepSeek Harness）时检测是否已安装：
/// 未安装则在框内先安装，安装完成前不能保存；已安装时可在此更新
class AgentEditorDialog extends StatefulWidget {
  const AgentEditorDialog({super.key, this.existing});

  final AgentSettings? existing;

  @override
  State<AgentEditorDialog> createState() => _AgentEditorDialogState();
}

class _AgentEditorDialogState extends State<AgentEditorDialog> {
  late AgentKind _kind = widget.existing?.kind ?? AgentKind.deepseekCli;
  late final _name = TextEditingController(text: widget.existing?.name ?? _defaultName(_kind));
  late final _endpoint = TextEditingController(text: widget.existing?.endpoint ?? '');
  late final _apiKey = TextEditingController(text: widget.existing?.apiKey ?? '');
  late final _model = TextEditingController(text: widget.existing?.model ?? '');
  late final _system = TextEditingController(text: widget.existing?.systemPrompt ?? '');
  late final AgentRuntimes _runtimes = context.read<AgentRuntimes>();

  /// 各类型的默认名称
  static String _defaultName(AgentKind k) => switch (k) {
    AgentKind.deepseekCli => 'DeepSeek Harness',
    AgentKind.openaiApi => 'OpenAI API',
  };

  @override
  void initState() {
    super.initState();
    // 运行环境安装完成后刷新保存按钮
    for (final r in _runtimes.all) {
      r.addListener(_onRuntime);
    }
  }

  void _onRuntime() {
    if (mounted) setState(() {});
  }

  /// 切换类型：名称仍是上一类型的默认名称时一并替换
  void _setKind(AgentKind k) {
    setState(() {
      if (_name.text.trim() == _defaultName(_kind)) _name.text = _defaultName(k);
      _kind = k;
    });
  }

  @override
  void dispose() {
    for (final r in _runtimes.all) {
      r.removeListener(_onRuntime);
    }
    for (final c in [_name, _endpoint, _apiKey, _model, _system]) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cli = _kind == AgentKind.deepseekCli;
    final runtime = _runtimes.of(_kind);
    final canSave = runtime == null || runtime.installed;
    return AppDialog(
      title: context.tr(widget.existing == null ? 'agent.new' : 'agent.edit'),
      width: 580,
      content: SizedBox(
        width: 532,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SegmentedButton<AgentKind>(
              segments: [
                ButtonSegment(value: AgentKind.deepseekCli, label: Text(_defaultName(AgentKind.deepseekCli))),
                ButtonSegment(value: AgentKind.openaiApi, label: Text(_defaultName(AgentKind.openaiApi))),
              ],
              selected: {_kind},
              onSelectionChanged: (s) => _setKind(s.first),
            ),
            if (runtime != null) ...[
              const SizedBox(height: 14),
              AgentRuntimeStatus(key: ValueKey(_kind), runtime: runtime),
            ],
            const SizedBox(height: 14),
            TextField(
              controller: _name,
              decoration: InputDecoration(labelText: context.tr('agent.name')),
            ),
            const SizedBox(height: 12),
            if (!cli) ...[
              TextField(
                controller: _endpoint,
                decoration: InputDecoration(labelText: context.tr('agent.endpoint'), hintText: 'https://api.deepseek.com'),
              ),
              const SizedBox(height: 12),
            ],
            TextField(
              controller: _apiKey,
              obscureText: true,
              decoration: InputDecoration(
                labelText: 'API Key',
                helperText: cli ? context.tr('agent.api_key.cli_helper') : null,
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _model,
              decoration: InputDecoration(
                labelText: context.tr(cli ? 'agent.model.dsh' : 'agent.model'),
                hintText: cli ? 'deepseek-v4-flash' : 'deepseek-chat',
                helperText: cli ? context.tr('agent.model.dsh_helper') : null,
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _system,
              maxLines: 3,
              decoration: InputDecoration(labelText: context.tr('agent.system_prompt'), alignLabelWithHint: true),
            ),
          ],
        ),
      ),
      actions: [
        OutlinedButton(onPressed: () => Navigator.pop(context), child: Text(context.tr('common.cancel'))),
        Tooltip(
          message: canSave ? '' : context.tr('runtime.save_requires', {'name': runtime.displayName}),
          child: FilledButton(onPressed: canSave ? _save : null, child: Text(context.tr('common.save'))),
        ),
      ],
    );
  }

  /// 保存并关闭
  void _save() {
    if (_name.text.trim().isEmpty) return;
    Navigator.pop(
      context,
      AgentSettings(
        uuid: widget.existing?.uuid ?? IdUtils.newId(),
        name: _name.text.trim(),
        kind: _kind,
        command: widget.existing?.command ?? '',
        args: widget.existing?.args ?? '',
        endpoint: _endpoint.text.trim(),
        apiKey: _apiKey.text.isEmpty ? null : _apiKey.text,
        model: _model.text.trim(),
        systemPrompt: _system.text,
        isActive: widget.existing?.isActive ?? false,
        createdAt: widget.existing?.createdAt ?? DateTime.now().millisecondsSinceEpoch,
      ),
    );
  }
}
