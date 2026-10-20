import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../l10n/app_localizations.dart';
import '../../../ui_kit/app_dialog.dart';
import '../../../utils/id_utils.dart';
import '../../ai/agent_config.dart';
import '../../ai/codex/codex_runtime_controller.dart';
import '../../ai/runtime/agent_runtime.dart';
import 'agent_runtime_status.dart';
import 'codex_account_panel.dart';
import 'openai_model_field.dart';

/// 添加 / 编辑 Agent。选择需要本地运行环境的类型（DeepSeek Harness、Codex）时检测是否已安装：
/// 未安装则在框内先安装，安装完成前不能保存；已安装时可在此更新。
/// Codex 在框内登录 ChatGPT 账号并从账号可用的模型中选择（登录目录以 Agent uuid 命名，放弃新建时删除）
class AgentEditorDialog extends StatefulWidget {
  const AgentEditorDialog({super.key, this.existing});

  final AgentSettings? existing;

  @override
  State<AgentEditorDialog> createState() => _AgentEditorDialogState();
}

class _AgentEditorDialogState extends State<AgentEditorDialog> {
  late AgentKind _kind = widget.existing?.kind ?? AgentKind.deepseekCli;

  /// Agent uuid：新建时提前生成，Codex 登录目录以它命名
  late final String _uuid = widget.existing?.uuid ?? IdUtils.newId();

  /// 是否已保存（新建后放弃时清理运行环境中的专属数据）
  bool _saved = false;
  late final _name = TextEditingController(text: widget.existing?.name ?? _defaultName(_kind));
  late final _endpoint = TextEditingController(text: widget.existing?.endpoint ?? '');
  late final _apiKey = TextEditingController(text: widget.existing?.apiKey ?? '');
  late final _model = TextEditingController(text: widget.existing?.model ?? '');
  late final _system = TextEditingController(text: widget.existing?.systemPrompt ?? '');

  /// API Key 是否隐藏显示
  bool _hideKey = true;

  /// 推理强度（Codex 在框内选择；其他类型保留聊天窗口中的选择）
  late String _effort = widget.existing?.reasoningEffort ?? '';
  late final AgentRuntimes _runtimes = context.read<AgentRuntimes>();

  /// 各类型的默认名称
  static String _defaultName(AgentKind k) => k.label;

  @override
  void initState() {
    super.initState();
    // 接口地址与模型变化时刷新保存按钮
    _endpoint.addListener(_onRuntime);
    _model.addListener(_onRuntime);
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
      // 新建的 Agent 没有保存：删除框内登录等产生的专属数据
      if (widget.existing == null && !_saved) r.removeAgentData(_uuid);
    }
    for (final c in [_name, _endpoint, _apiKey, _model, _system]) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cli = _kind == AgentKind.deepseekCli;
    final codex = _kind == AgentKind.codex;
    final runtime = _runtimes.of(_kind);
    // OpenAI 兼容 API 没有默认地址与模型，必须填写
    final missingApi = _kind == AgentKind.openaiApi && (_endpoint.text.trim().isEmpty || _model.text.trim().isEmpty);
    final canSave = (runtime == null || runtime.installed) && !missingApi;
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
                for (final k in const [AgentKind.deepseekCli, AgentKind.codex, AgentKind.openaiApi])
                  ButtonSegment(value: k, label: Text(_defaultName(k))),
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
            if (codex) ...[
              if (runtime != null && runtime.installed) ...[
                CodexAccountPanel(
                  runtime: runtime as CodexRuntimeController,
                  homeId: _uuid,
                  model: _model.text,
                  onModelChanged: (m) => setState(() => _model.text = m),
                  effort: _effort,
                  onEffortChanged: (e) => setState(() => _effort = e),
                ),
                const SizedBox(height: 12),
              ],
            ] else ...[
              if (!cli) ...[
                TextField(
                  controller: _endpoint,
                  decoration: InputDecoration(
                    labelText: context.tr('agent.endpoint'),
                  ),
                ),
                const SizedBox(height: 12),
              ],
              TextField(
                controller: _apiKey,
                obscureText: _hideKey,
                decoration: InputDecoration(
                  labelText: 'API Key',
                  helperText: context.tr(cli ? 'agent.api_key.cli_helper' : 'agent.api_key.local_helper'),
                  suffixIcon: IconButton(
                    tooltip: context.tr(_hideKey ? 'agent.api_key.show' : 'agent.api_key.hide'),
                    icon: Icon(_hideKey ? Icons.visibility_outlined : Icons.visibility_off_outlined, size: 20),
                    onPressed: () => setState(() => _hideKey = !_hideKey),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              if (cli)
                TextField(
                  controller: _model,
                  decoration: InputDecoration(
                    labelText: context.tr('agent.model.dsh'),
                    hintText: 'deepseek-v4-flash',
                    helperText: context.tr('agent.model.dsh_helper'),
                  ),
                )
              else
                OpenAiModelField(
                  controller: _model,
                  endpoint: () => _endpoint.text,
                  apiKey: () => _apiKey.text,
                ),
              const SizedBox(height: 12),
            ],
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
          message: canSave
              ? ''
              : (missingApi
                    ? context.tr('agent.openai.save_requires')
                    : context.tr('runtime.save_requires', {'name': runtime!.displayName})),
          child: FilledButton(onPressed: canSave ? _save : null, child: Text(context.tr('common.save'))),
        ),
      ],
    );
  }

  /// 保存并关闭
  void _save() {
    if (_name.text.trim().isEmpty) return;
    _saved = true;
    Navigator.pop(
      context,
      AgentSettings(
        uuid: _uuid,
        name: _name.text.trim(),
        kind: _kind,
        command: widget.existing?.command ?? '',
        args: widget.existing?.args ?? '',
        endpoint: _endpoint.text.trim(),
        // Codex 使用账号登录，不保存 API Key
        apiKey: _apiKey.text.isEmpty || _kind == AgentKind.codex ? null : _apiKey.text,
        model: _model.text.trim(),
        systemPrompt: _system.text,
        reasoningEffort: _effort,
        isActive: widget.existing?.isActive ?? false,
        createdAt: widget.existing?.createdAt ?? DateTime.now().millisecondsSinceEpoch,
      ),
    );
  }
}
