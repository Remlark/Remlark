import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../app/theme/app_palette.dart';
import '../../../l10n/app_localizations.dart';
import '../../../ui_kit/app_dialog.dart';
import '../../../ui_kit/check_label.dart';
import '../../../ui_kit/buttons.dart';
import '../../../ui_kit/panel.dart';
import '../../../ui_kit/tags.dart';
import '../../ai/agent_config.dart';
import '../../ai/agent_options_controller.dart';
import '../../ai/agents_controller.dart';
import '../../ai/runtime/agent_runtime.dart';
import 'agent_editor_dialog.dart';
import 'settings_card.dart';

/// AI Agent 设置：添加、编辑、删除 Agent（当前使用哪个 Agent 在聊天窗口中切换）。
/// 需要本地运行环境的 Agent 在添加 / 编辑时安装，列表中显示运行环境状态
class AgentSettingsSection extends StatefulWidget {
  const AgentSettingsSection({super.key});

  @override
  State<AgentSettingsSection> createState() => _AgentSettingsSectionState();
}

class _AgentSettingsSectionState extends State<AgentSettingsSection> {
  late final AgentRuntimes _runtimes = context.read<AgentRuntimes>();

  @override
  void initState() {
    super.initState();
    // 只读取各运行环境的本机安装状态（列表中显示未安装 / 正在安装）；检测更新在编辑框中进行
    for (final r in _runtimes.all) {
      r.addListener(_onRuntime);
      r.loadLocal();
    }
  }

  void _onRuntime() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    for (final r in _runtimes.all) {
      r.removeListener(_onRuntime);
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.watch<AgentsController>();
    final p = context.palette;
    return SettingsCard(
      title: context.tr('settings.agents'),
      description: context.tr('settings.agents.desc'),
      trailing: FilledButton.icon(
        icon: const Icon(Icons.add, size: 18),
        label: Text(context.tr('agent.new')),
        onPressed: () => _edit(context),
      ),
      children: [
        if (c.agents.isNotEmpty) const SizedBox(height: 16),
        for (final a in c.agents)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: AppPanel(
              padding: const EdgeInsets.fromLTRB(16, 12, 12, 12),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Flexible(
                              child: Text(
                                a.name,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: p.text),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Tag(switch (a.kind) {
                              AgentKind.deepseekCli => 'dsh',
                              AgentKind.codex => 'Codex',
                              AgentKind.openaiApi => 'API',
                            }, color: p.info),
                          ],
                        ),
                        const SizedBox(height: 4),
                        _subtitle(context, a),
                      ],
                    ),
                  ),
                  GhostIconButton(
                    icon: Icons.edit_outlined,
                    tooltip: context.tr('common.edit'),
                    onPressed: () => _edit(context, a),
                  ),
                  GhostIconButton(
                    icon: Icons.delete_outline,
                    tooltip: context.tr('common.delete'),
                    onPressed: () => _delete(context, a),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }

  /// 副标题：类型与模型；需要运行环境时附上未安装 / 正在安装提示（是否可更新只在编辑框中显示）
  Widget _subtitle(BuildContext context, AgentSettings a) {
    final p = context.palette;
    final runtime = _runtimes.of(a.kind);
    final model = a.model.isEmpty ? context.tr('agent.model.default') : a.model;
    final base = switch (a.kind) {
      AgentKind.deepseekCli => 'DeepSeek Harness · $model',
      AgentKind.codex => 'Codex · $model',
      AgentKind.openaiApi => '${a.kind.label} · ${a.model.isEmpty ? context.tr('ai.model.none') : a.model}',
    };
    final String? hint;
    Color hintColor = p.warning;
    if (runtime == null || !runtime.loaded) {
      hint = null;
    } else if (runtime.busy) {
      hint = context.tr('runtime.installing', {'name': runtime.displayName});
      hintColor = p.info;
    } else if (!runtime.installed) {
      hint = context.tr('runtime.not_installed');
    } else {
      hint = null;
    }
    final style = TextStyle(fontSize: 13, color: p.textMuted, fontFamily: 'monospace');
    return Text.rich(
      TextSpan(
        text: base,
        children: [
          if (hint != null) TextSpan(text: ' · $hint', style: style.copyWith(color: hintColor)),
        ],
      ),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: style,
    );
  }

  /// 添加或编辑 Agent
  Future<void> _edit(BuildContext context, [AgentSettings? a]) async {
    final r = await showDialog<AgentSettings>(
      context: context,
      builder: (_) => AgentEditorDialog(existing: a),
    );
    if (r == null || !context.mounted) return;
    // API Key 等配置可能变化：模型与推理强度的可选项下次使用时重新读取
    context.read<AgentOptionsController>().forget(r.uuid);
    await context.read<AgentsController>().save(r);
  }

  /// 删除 Agent；删除的是使用某运行环境的最后一个 Agent 时，可选择一并移除运行环境
  Future<void> _delete(BuildContext context, AgentSettings a) async {
    final c = context.read<AgentsController>();
    final runtime = _runtimes.of(a.kind);
    final lastUser = runtime != null && runtime.installed && !c.agents.any((o) => o.uuid != a.uuid && o.kind == a.kind);
    final r = await showDialog<(bool, bool)>(
      context: context,
      builder: (_) => _DeleteAgentDialog(name: a.name, runtime: lastUser ? runtime : null),
    );
    if (r == null || !r.$1) return;
    await c.delete(a.uuid);
    // 删除该 Agent 的专属数据（如 Codex 的登录目录）
    await runtime?.removeAgentData(a.uuid);
    if (r.$2) await runtime!.uninstall();
  }
}

/// 删除 Agent 确认框；[runtime] 非空时提供“同时移除运行环境”（默认不勾选）。
/// 返回 (是否删除, 是否移除运行环境)
class _DeleteAgentDialog extends StatefulWidget {
  const _DeleteAgentDialog({required this.name, this.runtime});

  final String name;
  final AgentRuntime? runtime;

  @override
  State<_DeleteAgentDialog> createState() => _DeleteAgentDialogState();
}

class _DeleteAgentDialogState extends State<_DeleteAgentDialog> {
  bool _removeRuntime = false;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final runtime = widget.runtime;
    return AppDialog(
      title: context.tr('agent.delete'),
      icon: Icons.delete_outline_rounded,
      iconColor: p.danger,
      content: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(widget.name, style: const TextStyle(height: 1.5)),
          if (runtime != null) ...[
            const SizedBox(height: 10),
            CheckLabel(
              value: _removeRuntime,
              onChanged: (v) => setState(() => _removeRuntime = v),
              label: context.tr('runtime.remove_with_agent', {'name': runtime.displayName}),
              helper: context.tr('runtime.remove_with_agent.helper'),
            ),
          ],
        ],
      ),
      actions: [
        OutlinedButton(onPressed: () => Navigator.pop(context), child: Text(context.tr('common.cancel'))),
        DangerButton(label: context.tr('common.delete'), onPressed: () => Navigator.pop(context, (true, _removeRuntime))),
      ],
    );
  }
}
