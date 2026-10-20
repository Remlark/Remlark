import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../app/nav_controller.dart';
import '../../../app/theme/app_palette.dart';
import '../../../l10n/app_localizations.dart';
import '../../../ui_kit/app_menu.dart';
import '../agent_config.dart';
import '../agent_options_controller.dart';
import '../agents_controller.dart';
import '../runtime/agent_options.dart';

/// 推理强度的显示名称：已知取值翻译，其他原样显示
String effortLabel(BuildContext context, String effort) {
  const known = {'off', 'none', 'minimal', 'low', 'medium', 'high', 'xhigh', 'max', 'ultra'};
  return known.contains(effort) ? context.tr('effort.$effort') : effort;
}

/// 聊天窗口顶部的 Agent、模型与推理强度选择（紧凑样式，各一个下拉菜单）。
/// Agent 在这里切换（设置页只负责添加、编辑、删除；已有消息的聊天换 Agent 会新建对话）；模型与推理强度保存到当前 Agent 的配置，每个 Agent 各自记住。
/// 可选项首次显示时读取：dsh、Codex 来自运行环境，OpenAI 兼容 API 来自接口的模型列表（推理强度固定为默认）；
/// 运行环境未安装时只显示配置的模型
class AgentModelSelector extends StatelessWidget {
  const AgentModelSelector({
    super.key,
    required this.agents,
    required this.agent,
    required this.onAgentChanged,
    this.enabled = true,
  });

  /// 全部 Agent（切换菜单）
  final List<AgentSettings> agents;

  /// 当前聊天使用的 Agent
  final AgentSettings agent;

  /// 选择了其他 Agent（由聊天面板决定是否新建对话）
  final ValueChanged<String> onAgentChanged;

  /// 回答进行中不能切换
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final options = context.watch<AgentOptionsController>();
    final supported = options.supports(agent);
    final opts = options.of(agent.uuid);
    if (supported && opts == null && !options.loading(agent.uuid) && options.error(agent.uuid) == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) => options.load(agent));
    }
    final model = opts?.modelFor(agent.model);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        // 空间不足时优先保留 Agent 名称，先截断模型名
        Flexible(flex: 3, child: _agentChip(context)),
        Flexible(flex: 2, child: _modelChip(context, options, opts, supported)),
        _effortChip(context, model, supported),
      ],
    );
  }

  /// Agent：列出全部 Agent（附类型），底部“管理 Agent”跳到设置页
  Widget _agentChip(BuildContext context) {
    const manage = '\u0000manage';
    return AppMenuAnchor<String>(
      selected: agent.uuid,
      minWidth: 220,
      maxWidth: 320,
      onSelected: (v) => v == manage
          ? context.read<NavController>().goSettings(SettingsSection.agents)
          : onAgentChanged(v),
      items: (context) => [
        for (final a in agents)
          AppMenuItem(
            value: a.uuid,
            label: a.name,
            // 名称与类型相同时不重复显示
            description: a.name == a.kind.label ? null : a.kind.label,
          ),
        const AppMenuDivider(),
        AppMenuItem(value: manage, icon: Icons.settings_outlined, label: context.tr('ai.agent.manage')),
      ],
      builder: (context, open) => _Chip(
        icon: Icons.auto_awesome_outlined,
        label: agent.name,
        tooltip: context.tr('ai.agent.tooltip'),
        strong: true,
        onTap: enabled ? open : null,
      ),
    );
  }


  /// 模型：第一项为默认模型，菜单底部可刷新列表
  Widget _modelChip(BuildContext context, AgentOptionsController options, AgentOptions? opts, bool supported) {
    final def = opts?.defaultModel;
    final String label;
    if (agent.model.isNotEmpty) {
      label = opts?.modelFor(agent.model)?.label ?? agent.model;
    } else if (agent.kind == AgentKind.openaiApi) {
      // OpenAI 兼容 API 没有默认模型，需要选择
      label = context.tr('ai.model.none');
    } else {
      label = def?.label ?? context.tr('agent.model.default');
    }
    if (!supported) return _Chip(icon: Icons.memory_rounded, label: label, tooltip: context.tr('ai.model.fixed'));
    const refresh = '\u0000refresh';
    return AppMenuAnchor<String>(
      selected: agent.model,
      minWidth: 220,
      maxWidth: 320,
      onSelected: (v) => v == refresh ? options.load(agent, force: true) : _save(context, model: v, opts: opts),
      items: (context) => [
        if (opts != null) ...[
          if (opts.hasDefault)
            AppMenuItem(
              value: '',
              label: def == null
                  ? context.tr('agent.model.default')
                  : context.tr('ai.model.default_named', {'name': def.label}),
            ),
          for (final m in opts.models) AppMenuItem(value: m.id, label: m.label),
          if (opts.models.isEmpty) AppMenuItem(label: context.tr('ai.model.empty'), enabled: false),
        ] else
          AppMenuItem(
            label: options.error(agent.uuid) ?? context.tr('ai.model.loading'),
            enabled: false,
          ),
        const AppMenuDivider(),
        AppMenuItem(value: refresh, icon: Icons.refresh_rounded, label: context.tr('ai.model.refresh')),
      ],
      builder: (context, open) => _Chip(
        icon: Icons.memory_rounded,
        label: label,
        tooltip: context.tr('ai.model.tooltip'),
        onTap: enabled ? open : null,
      ),
    );
  }

  /// 推理强度：选项随模型变化；模型不支持选择时固定为默认
  Widget _effortChip(BuildContext context, AgentModelOption? model, bool supported) {
    final efforts = model?.efforts ?? const <String>[];
    final current = agent.reasoningEffort.isNotEmpty && efforts.contains(agent.reasoningEffort)
        ? agent.reasoningEffort
        : '';
    final def = model?.defaultEffort;
    final defaultLabel = def == null
        ? context.tr('effort.default')
        : context.tr('effort.default_named', {'name': effortLabel(context, def)});
    final label = current.isEmpty ? (def == null ? context.tr('effort.default') : effortLabel(context, def)) : effortLabel(context, current);
    if (!supported || efforts.isEmpty) {
      return _Chip(icon: Icons.psychology_outlined, label: context.tr('effort.default'), tooltip: context.tr('effort.fixed'));
    }
    return AppMenuAnchor<String>(
      selected: current,
      minWidth: 160,
      onSelected: (v) => _save(context, effort: v),
      items: (context) => [
        AppMenuItem(value: '', label: defaultLabel),
        for (final e in efforts) AppMenuItem(value: e, label: effortLabel(context, e)),
      ],
      builder: (context, open) => _Chip(
        icon: Icons.psychology_outlined,
        label: label,
        tooltip: context.tr('effort.tooltip'),
        onTap: enabled ? open : null,
      ),
    );
  }

  /// 保存到 Agent 配置；切换模型时，新模型不支持当前推理强度则改回默认
  void _save(BuildContext context, {String? model, String? effort, AgentOptions? opts}) {
    var newEffort = effort ?? agent.reasoningEffort;
    if (model != null && newEffort.isNotEmpty) {
      final efforts = opts?.modelFor(model)?.efforts ?? const <String>[];
      if (!efforts.contains(newEffort)) newEffort = '';
    }
    context.read<AgentsController>().save(agent.copyWith(model: model, reasoningEffort: newEffort));
  }
}

/// 紧凑的选择按钮：图标 + 文字 + 下拉箭头；[onTap] 为 null 时只显示（不支持选择或回答进行中）
class _Chip extends StatelessWidget {
  const _Chip({required this.icon, required this.label, required this.tooltip, this.onTap, this.strong = false});

  final IconData icon;
  final String label;
  final String tooltip;
  final VoidCallback? onTap;

  /// 主要选项（Agent）用正文颜色与较大字号
  final bool strong;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final color = strong ? p.text : p.textMuted;
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(6),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 15, color: color),
              const SizedBox(width: 4),
              Flexible(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: strong ? 13 : 11.5,
                    color: color,
                    fontWeight: strong ? FontWeight.w600 : FontWeight.w500,
                  ),
                ),
              ),
              if (onTap != null) Icon(Icons.arrow_drop_down_rounded, size: 18, color: color),
            ],
          ),
        ),
      ),
    );
  }
}
