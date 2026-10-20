import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../../app/theme/app_palette.dart';
import '../../../app/theme/app_theme.dart';
import '../../../l10n/app_localizations.dart';
import '../../../ui_kit/app_menu.dart';
import '../../../ui_kit/buttons.dart';
import '../../../ui_kit/tags.dart';
import '../../../utils/platform_utils.dart';
import '../../../utils/ui_utils.dart';
import '../../ai/codex/codex_account_service.dart';
import '../../ai/codex/codex_runtime_controller.dart';
import '../../ai/agent_options_controller.dart';
import '../../ai/codex/codex_types.dart';
import '../../ai/ui/agent_model_selector.dart';

/// Codex Agent 编辑框中的账号与模型：
/// 未登录时提供“登录 ChatGPT”（在浏览器中完成），登录中可取消或复制登录链接，已登录显示账号并可退出；
/// 模型从 Codex 读取，打开时与登录后自动刷新，也可手动刷新。每个 Agent 使用自己的 CODEX_HOME（[homeId]）
class CodexAccountPanel extends StatefulWidget {
  const CodexAccountPanel({
    super.key,
    required this.runtime,
    required this.homeId,
    required this.model,
    required this.onModelChanged,
    required this.effort,
    required this.onEffortChanged,
  });

  final CodexRuntimeController runtime;
  final String homeId;

  /// 当前选择的模型，空字符串为 Codex 默认模型
  final String model;
  final ValueChanged<String> onModelChanged;

  /// 当前选择的推理强度，空字符串为模型默认
  final String effort;
  final ValueChanged<String> onEffortChanged;

  @override
  State<CodexAccountPanel> createState() => _CodexAccountPanelState();
}

class _CodexAccountPanelState extends State<CodexAccountPanel> {
  CodexAccount? _account;
  List<CodexModel> _models = const [];
  bool _loadingAccount = false;
  bool _loadingModels = false;
  CodexLoginSession? _login;
  String? _error;
  bool _wasInstalled = false;

  CodexAccountService get _accounts => widget.runtime.accounts;

  @override
  void initState() {
    super.initState();
    _wasInstalled = widget.runtime.installed;
    widget.runtime.addListener(_onRuntime);
    if (_wasInstalled) _refresh();
  }

  @override
  void dispose() {
    widget.runtime.removeListener(_onRuntime);
    // 关闭编辑框时取消未完成的登录，结束等待回调的进程
    _login?.cancel();
    super.dispose();
  }

  /// 运行环境刚安装完成时读取账号与模型
  void _onRuntime() {
    final installed = widget.runtime.installed;
    if (installed && !_wasInstalled) _refresh();
    _wasInstalled = installed;
  }

  /// 依次读取账号与模型列表（不同时启动多个 Codex 进程）
  Future<void> _refresh() async {
    await _loadAccount();
    if (mounted) await _loadModels();
  }

  Future<void> _loadAccount() async {
    setState(() => _loadingAccount = true);
    try {
      final a = await _accounts.readAccount(widget.homeId);
      if (!mounted) return;
      setState(() => _account = a);
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _loadingAccount = false);
    }
  }

  Future<void> _loadModels() async {
    setState(() => _loadingModels = true);
    try {
      final models = await _accounts.listModels(widget.homeId);
      if (!mounted) return;
      setState(() {
        _models = models;
        _error = null;
      });
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _loadingModels = false);
    }
  }

  /// 开始浏览器登录；完成后自动刷新账号与模型
  Future<void> _startLogin() async {
    setState(() => _error = null);
    final CodexLoginSession session;
    try {
      session = await _accounts.startLogin(widget.homeId);
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
      return;
    }
    if (!mounted) {
      await session.cancel();
      return;
    }
    setState(() => _login = session);
    await PlatformUtils.openUrl(session.authUrl);
    try {
      final account = await session.completed;
      if (!mounted || account == null) return;
      setState(() => _account = account);
      // 账号变化：聊天窗口的模型列表也需要重新读取
      context.read<AgentOptionsController>().forget(widget.homeId);
      await _loadModels();
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    } finally {
      if (mounted && identical(_login, session)) setState(() => _login = null);
    }
  }

  /// 退出登录
  Future<void> _logout() async {
    setState(() => _loadingAccount = true);
    try {
      await _accounts.logout(widget.homeId);
      if (!mounted) return;
      setState(() => _account = null);
      context.read<AgentOptionsController>().forget(widget.homeId);
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _loadingAccount = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 12, 12),
      decoration: BoxDecoration(
        color: p.panelRaised,
        borderRadius: BorderRadius.circular(AppSizes.radius),
        border: Border.all(color: p.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(child: _accountStatus(context)),
              const SizedBox(width: 12),
              ..._accountActions(context),
            ],
          ),
          const SizedBox(height: 12),
          Text(context.tr('codex.model_effort'), style: TextStyle(fontSize: 12.5, color: p.textMuted)),
          const SizedBox(height: 6),
          Row(
            children: [
              Expanded(flex: 3, child: _modelDropdown(context)),
              const SizedBox(width: 8),
              Expanded(flex: 2, child: _effortDropdown(context)),
              const SizedBox(width: 6),
              _loadingModels
                  ? const SizedBox(
                      width: 32,
                      height: 32,
                      child: Padding(padding: EdgeInsets.all(8), child: CircularProgressIndicator(strokeWidth: 2)),
                    )
                  : GhostIconButton(
                      icon: Icons.refresh_rounded,
                      tooltip: context.tr('codex.models.refresh'),
                      onPressed: _account == null ? null : _loadModels,
                    ),
            ],
          ),
          if (_error != null) ...[
            const SizedBox(height: 8),
            SelectableText(_error!, style: TextStyle(fontSize: 12.5, color: p.danger)),
          ],
        ],
      ),
    );
  }

  /// 账号状态文字
  Widget _accountStatus(BuildContext context) {
    final p = context.palette;
    final muted = TextStyle(fontSize: 12.5, color: p.textMuted, height: 1.4);
    if (_login != null) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            context.tr('codex.login.waiting'),
            style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: p.text),
          ),
          const SizedBox(height: 3),
          Text(context.tr('codex.login.waiting.desc'), style: muted),
        ],
      );
    }
    if (_loadingAccount && _account == null) return Text(context.tr('codex.account.loading'), style: muted);
    final a = _account;
    if (a == null) {
      return StatusText(
        text: context.tr('codex.account.signed_out'),
        color: p.warning,
        icon: Icons.person_off_outlined,
      );
    }
    final who = a.email ?? context.tr('codex.account.api_key');
    final plan = a.planLabel;
    return StatusText(text: plan == null ? who : '$who · $plan', color: p.success, icon: Icons.account_circle_outlined);
  }

  /// 账号操作：同一时间只有一个主要操作（登录 / 取消登录 / 退出登录）
  List<Widget> _accountActions(BuildContext context) {
    final login = _login;
    if (login != null) {
      return [
        GhostIconButton(
          icon: Icons.link_rounded,
          tooltip: context.tr('codex.login.copy_link'),
          onPressed: () {
            Clipboard.setData(ClipboardData(text: login.authUrl));
            UiUtils.toast(context.tr('common.copied'));
          },
        ),
        const SizedBox(width: 6),
        OutlinedButton(onPressed: login.cancel, child: Text(context.tr('common.cancel'))),
      ];
    }
    if (_account == null) {
      return [
        FilledButton.icon(
          icon: const Icon(Icons.login_rounded, size: 18),
          label: Text(context.tr('codex.login')),
          onPressed: _loadingAccount ? null : _startLogin,
        ),
      ];
    }
    return [OutlinedButton(onPressed: _loadingAccount ? null : _logout, child: Text(context.tr('codex.logout')))];
  }

  /// 模型选择：第一项为 Codex 默认模型；已保存但不在列表中的模型仍保留为选项
  Widget _modelDropdown(BuildContext context) {
    final def = _models.where((m) => m.isDefault).firstOrNull;
    final defaultLabel = def == null
        ? context.tr('agent.model.default')
        : context.tr('codex.model.default_named', {'name': def.displayName});
    return AppDropdown<String>(
      value: widget.model,
      items: [
        AppMenuItem(value: '', label: defaultLabel),
        for (final m in _models)
          AppMenuItem(value: m.id, label: m.displayName, description: m.id == m.displayName ? null : m.id),
        if (widget.model.isNotEmpty && !_models.any((m) => m.id == widget.model))
          AppMenuItem(value: widget.model, label: widget.model),
      ],
      // 未登录时 model/list 返回的是 Codex 内置的模型目录，不代表账号实际可用的模型：登录后才能选择
      onChanged: _account == null
          ? null
          : (v) {
              final model = v ?? '';
              widget.onModelChanged(model);
              // 新模型不支持当前推理强度时改回默认
              if (widget.effort.isNotEmpty && !_efforts(model).contains(widget.effort)) widget.onEffortChanged('');
            },
    );
  }

  /// 模型 [model]（空为默认模型）支持的推理强度
  List<String> _efforts(String model) {
    final m = model.isEmpty
        ? _models.where((m) => m.isDefault).firstOrNull
        : _models.where((m) => m.id == model).firstOrNull;
    return m?.efforts ?? const [];
  }

  /// 推理强度选择：第一项为模型默认；模型列表尚未读取时只有默认
  Widget _effortDropdown(BuildContext context) {
    final m = widget.model.isEmpty
        ? _models.where((m) => m.isDefault).firstOrNull
        : _models.where((m) => m.id == widget.model).firstOrNull;
    final efforts = m?.efforts ?? const <String>[];
    final def = m?.defaultEffort;
    return AppDropdown<String>(
      value: efforts.contains(widget.effort) ? widget.effort : '',
      items: [
        AppMenuItem(
          value: '',
          label: def == null
              ? context.tr('effort.default')
              : context.tr('effort.default_named', {'name': effortLabel(context, def)}),
        ),
        for (final e in efforts) AppMenuItem(value: e, label: effortLabel(context, e)),
      ],
      onChanged: efforts.isEmpty || _account == null ? null : (v) => widget.onEffortChanged(v ?? ''),
    );
  }
}
