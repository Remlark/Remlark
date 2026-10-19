import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../l10n/app_localizations.dart';
import '../../../utils/id_utils.dart';
import '../../../utils/ui_utils.dart';
import '../../ai/agent_config.dart';
import '../../ai/agents_controller.dart';
import 'settings_card.dart';

/// AI Agent 设置：配置多个 Agent，选择当前使用的 Agent
class AgentSettingsSection extends StatelessWidget {
  const AgentSettingsSection({super.key});

  @override
  Widget build(BuildContext context) {
    final c = context.watch<AgentsController>();
    final active = c.active;
    return SettingsCard(
      title: context.tr('settings.agents'),
      trailing: TextButton.icon(
        icon: const Icon(Icons.add, size: 16),
        label: Text(context.tr('agent.new')),
        onPressed: () => _edit(context),
      ),
      children: [
        if (c.agents.isEmpty) Text(context.tr('agent.empty'), style: Theme.of(context).textTheme.bodySmall),
        RadioGroup<String>(
          groupValue: active?.uuid,
          onChanged: (v) => v == null ? null : c.setActive(v),
          child: Column(
            children: [
              for (final a in c.agents)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Radio<String>(value: a.uuid),
                  title: Text(a.name),
                  subtitle: Text(
                    a.kind == AgentKind.deepseekCli
                        ? 'DeepSeek Harness CLI · ${a.command.isEmpty ? 'dsh' : a.command}'
                        : 'OpenAI API · ${a.model.isEmpty ? 'deepseek-chat' : a.model}',
                  ),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(icon: const Icon(Icons.edit_outlined, size: 18), onPressed: () => _edit(context, a)),
                      IconButton(
                        icon: const Icon(Icons.delete_outline, size: 18),
                        onPressed: () async {
                          final ok = await UiUtils.confirm(
                            context,
                            title: context.tr('agent.delete'),
                            message: a.name,
                            danger: true,
                          );
                          if (ok) await c.delete(a.uuid);
                        },
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }

  Future<void> _edit(BuildContext context, [AgentSettings? a]) async {
    final r = await showDialog<AgentSettings>(
      context: context,
      builder: (_) => _AgentDialog(existing: a),
    );
    if (r != null && context.mounted) await context.read<AgentsController>().save(r);
  }
}

class _AgentDialog extends StatefulWidget {
  const _AgentDialog({this.existing});

  final AgentSettings? existing;

  @override
  State<_AgentDialog> createState() => _AgentDialogState();
}

class _AgentDialogState extends State<_AgentDialog> {
  late AgentKind _kind = widget.existing?.kind ?? AgentKind.deepseekCli;
  late final _name = TextEditingController(text: widget.existing?.name ?? 'DeepSeek Harness');
  late final _command = TextEditingController(text: widget.existing?.command ?? '');
  late final _args = TextEditingController(text: widget.existing?.args ?? '');
  late final _endpoint = TextEditingController(text: widget.existing?.endpoint ?? '');
  late final _apiKey = TextEditingController(text: widget.existing?.apiKey ?? '');
  late final _model = TextEditingController(text: widget.existing?.model ?? '');
  late final _system = TextEditingController(text: widget.existing?.systemPrompt ?? '');

  @override
  Widget build(BuildContext context) {
    final cli = _kind == AgentKind.deepseekCli;
    return AlertDialog(
      title: Text(context.tr(widget.existing == null ? 'agent.new' : 'agent.edit')),
      content: SizedBox(
        width: 520,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SegmentedButton<AgentKind>(
                segments: const [
                  ButtonSegment(value: AgentKind.deepseekCli, label: Text('DeepSeek Harness CLI')),
                  ButtonSegment(value: AgentKind.openaiApi, label: Text('OpenAI API')),
                ],
                selected: {_kind},
                onSelectionChanged: (s) => setState(() => _kind = s.first),
              ),
              const SizedBox(height: 14),
              TextField(
                controller: _name,
                decoration: InputDecoration(labelText: context.tr('agent.name')),
              ),
              const SizedBox(height: 12),
              if (cli) ...[
                TextField(
                  controller: _command,
                  decoration: InputDecoration(labelText: context.tr('agent.command'), hintText: 'dsh'),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _args,
                  decoration: InputDecoration(
                    labelText: context.tr('agent.args'),
                    hintText: '--profile headless --json',
                    helperText: context.tr('agent.args.helper'),
                  ),
                ),
              ] else ...[
                TextField(
                  controller: _endpoint,
                  decoration: InputDecoration(
                    labelText: context.tr('agent.endpoint'),
                    hintText: 'https://api.deepseek.com',
                  ),
                ),
              ],
              const SizedBox(height: 12),
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
                  labelText: context.tr('agent.model'),
                  hintText: cli ? 'deepseek-harness' : 'deepseek-chat',
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
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: Text(context.tr('common.cancel'))),
        FilledButton(
          onPressed: () {
            if (_name.text.trim().isEmpty) return;
            Navigator.pop(
              context,
              AgentSettings(
                uuid: widget.existing?.uuid ?? IdUtils.newId(),
                name: _name.text.trim(),
                kind: _kind,
                command: _command.text.trim(),
                args: _args.text.trim(),
                endpoint: _endpoint.text.trim(),
                apiKey: _apiKey.text.isEmpty ? null : _apiKey.text,
                model: _model.text.trim(),
                systemPrompt: _system.text,
                isActive: widget.existing?.isActive ?? false,
                createdAt: widget.existing?.createdAt ?? DateTime.now().millisecondsSinceEpoch,
              ),
            );
          },
          child: Text(context.tr('common.save')),
        ),
      ],
    );
  }
}
