import 'package:flutter/material.dart';

import '../../../app/theme/app_palette.dart';
import '../../../app/theme/app_theme.dart';
import '../../../l10n/app_localizations.dart';
import '../../../ui_kit/tags.dart';
import '../../../utils/ui_utils.dart';
import '../../ai/runtime/agent_runtime.dart';

/// Agent 编辑框中的运行环境状态：未安装时提示并提供“安装”，已安装时显示版本，
/// 有新版本时提供“更新”，否则提供“检查更新”。同一时间只有一个操作按钮。
/// 只依赖 [AgentRuntime] 接口，各类需要本地运行环境的 Agent 共用
class AgentRuntimeStatus extends StatefulWidget {
  const AgentRuntimeStatus({super.key, required this.runtime});

  final AgentRuntime runtime;

  @override
  State<AgentRuntimeStatus> createState() => _AgentRuntimeStatusState();
}

class _AgentRuntimeStatusState extends State<AgentRuntimeStatus> {
  bool _checking = false;

  @override
  void initState() {
    super.initState();
    // 打开编辑框时检测更新（按缓存时间联网查询最新版本）
    widget.runtime.checkUpdate();
  }

  @override
  void didUpdateWidget(AgentRuntimeStatus old) {
    super.didUpdateWidget(old);
    if (old.runtime != widget.runtime) widget.runtime.checkUpdate();
  }

  /// 手动检查更新
  Future<void> _check() async {
    final r = widget.runtime;
    setState(() => _checking = true);
    await r.checkUpdate(force: true);
    if (!mounted) return;
    setState(() => _checking = false);
    if (r.error == null && !r.updateAvailable) UiUtils.toast(context.tr('runtime.latest'));
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.runtime,
      builder: (context, _) {
        final r = widget.runtime;
        final p = context.palette;
        final missing = r.loaded && !r.installed;
        return Container(
          padding: const EdgeInsets.fromLTRB(14, 12, 12, 12),
          decoration: BoxDecoration(
            color: missing && !r.busy ? p.warningSoft : p.panelRaised,
            borderRadius: BorderRadius.circular(AppSizes.radius),
            border: Border.all(color: missing && !r.busy ? p.warning.withValues(alpha: 0.5) : p.border),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(child: _status(context, r)),
                  const SizedBox(width: 12),
                  ?_action(context, r),
                ],
              ),
              if (r.busy) ...[
                const SizedBox(height: 10),
                LinearProgressIndicator(value: r.progress, minHeight: 3),
              ],
              if (r.error != null && !r.busy) ...[
                const SizedBox(height: 8),
                SelectableText(r.error!, style: TextStyle(fontSize: 12.5, color: p.danger)),
              ],
            ],
          ),
        );
      },
    );
  }

  /// 状态文字：安装中显示阶段，未安装显示需要安装的说明，已安装显示版本与是否最新
  Widget _status(BuildContext context, AgentRuntime r) {
    final p = context.palette;
    final title = TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: p.text);
    final muted = TextStyle(fontSize: 12.5, color: p.textMuted, height: 1.4);
    if (r.busy) {
      final pct = r.progress == null ? '' : ' ${(r.progress! * 100).round()}%';
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(context.tr('runtime.installing', {'name': r.displayName}), style: title),
          const SizedBox(height: 3),
          Text('${context.tr(r.stageKey!, r.stageArgs)}$pct', style: muted),
        ],
      );
    }
    if (!r.loaded) return const SizedBox(height: 36);
    if (!r.installed) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(context.tr('runtime.required', {'name': r.displayName}), style: title),
          const SizedBox(height: 3),
          Text(context.tr(r.notInstalledKey), style: muted),
        ],
      );
    }
    final version = '${r.displayName} v${r.installedVersion}';
    if (r.updateAvailable) {
      return StatusText(
        text: '$version · ${context.tr('runtime.update_available', {'version': r.latestVersion})}',
        color: p.warning,
        icon: Icons.arrow_circle_up_rounded,
      );
    }
    return StatusText(
      text: r.latestVersion == null ? version : '$version · ${context.tr('runtime.latest')}',
      color: p.success,
      icon: Icons.check_circle_outline_rounded,
    );
  }

  /// 唯一的操作按钮：安装 / 更新 / 检查更新
  Widget? _action(BuildContext context, AgentRuntime r) {
    if (!r.loaded) return null;
    if (!r.installed) {
      return FilledButton.icon(
        icon: const Icon(Icons.download_rounded, size: 18),
        label: Text(context.tr('runtime.install')),
        onPressed: r.busy ? null : r.install,
      );
    }
    if (r.updateAvailable) {
      return FilledButton.icon(
        icon: const Icon(Icons.upgrade_rounded, size: 18),
        label: Text(context.tr('runtime.update')),
        onPressed: r.busy ? null : r.install,
      );
    }
    return OutlinedButton(
      onPressed: r.busy || _checking ? null : _check,
      child: Text(context.tr('runtime.check_update')),
    );
  }
}
