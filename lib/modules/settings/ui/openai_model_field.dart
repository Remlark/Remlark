import 'package:flutter/material.dart';

import '../../../l10n/app_localizations.dart';
import '../../../ui_kit/app_menu.dart';
import '../../ai/agents/openai_models.dart';

/// OpenAI 兼容接口的模型输入框：右侧“获取列表”读取接口的 `/models`，在输入框下方列出供选择；
/// 也可以直接输入（接口不提供模型列表时）。接口地址与 API Key 取自编辑框中当前填写的值
class OpenAiModelField extends StatefulWidget {
  const OpenAiModelField({super.key, required this.controller, required this.endpoint, required this.apiKey});

  final TextEditingController controller;

  /// 当前填写的接口地址与 API Key
  final String Function() endpoint;
  final String Function() apiKey;

  @override
  State<OpenAiModelField> createState() => _OpenAiModelFieldState();
}

class _OpenAiModelFieldState extends State<OpenAiModelField> {
  bool _loading = false;
  String? _error;

  /// 读取模型列表并在输入框下方弹出选择
  Future<void> _fetch(BuildContext fieldContext) async {
    if (widget.endpoint().trim().isEmpty) {
      setState(() => _error = context.tr('agent.endpoint.fill_first'));
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    List<String> models;
    try {
      final key = widget.apiKey();
      models = await OpenAiModels.list(widget.endpoint(), key.isEmpty ? null : key);
    } catch (e) {
      if (mounted) setState(() => _error = context.tr('agent.model.fetch_failed', {'error': '$e'}));
      return;
    } finally {
      if (mounted) setState(() => _loading = false);
    }
    if (!mounted || !fieldContext.mounted) return;
    if (models.isEmpty) {
      setState(() => _error = context.tr('ai.model.empty'));
      return;
    }
    final picked = await AppMenu.showBelow<String>(
      fieldContext,
      [for (final m in models) AppMenuItem(value: m, label: m)],
      selected: widget.controller.text.trim(),
      matchWidth: true,
    );
    if (picked != null) widget.controller.text = picked;
  }

  @override
  Widget build(BuildContext context) {
    return Builder(
      builder: (fieldContext) => TextField(
        controller: widget.controller,
        decoration: InputDecoration(
          labelText: context.tr('agent.model.dsh'),
          errorText: _error,
          errorMaxLines: 3,
          suffixIcon: Padding(
            padding: const EdgeInsets.only(right: 4),
            child: _loading
                ? const Padding(
                    padding: EdgeInsets.all(14),
                    child: SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
                  )
                : TextButton(onPressed: () => _fetch(fieldContext), child: Text(context.tr('agent.model.fetch'))),
          ),
        ),
      ),
    );
  }
}
