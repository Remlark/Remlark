import 'package:flutter/foundation.dart';

import 'agent_config.dart';
import 'agents/openai_models.dart';
import 'runtime/agent_options.dart';
import 'runtime/agent_runtime.dart';

/// 各 Agent 可选的模型与推理强度（按 Agent uuid 缓存），聊天窗口与设置页共用。
/// dsh、Codex 由运行环境读取；OpenAI 兼容 API 从接口的 `/models` 读取模型，推理强度固定为默认
class AgentOptionsController extends ChangeNotifier {
  AgentOptionsController(this._runtimes);

  final AgentRuntimes _runtimes;
  final _options = <String, AgentOptions>{};
  final _errors = <String, String>{};
  final _loading = <String>{};

  /// Agent [uuid] 已读取的可选项，尚未读取或不支持时为 null
  AgentOptions? of(String uuid) => _options[uuid];

  /// 最近一次读取失败的原因
  String? error(String uuid) => _errors[uuid];

  /// 是否正在读取
  bool loading(String uuid) => _loading.contains(uuid);

  /// 该 Agent 是否支持选择模型（OpenAI 兼容 API，或有运行环境且已安装）
  bool supports(AgentSettings a) => a.kind == AgentKind.openaiApi || (_runtimes.of(a.kind)?.installed ?? false);

  /// 读取可选项：OpenAI 兼容 API 查询接口，其他由运行环境读取
  Future<AgentOptions> _read(AgentSettings a, bool force) {
    if (a.kind == AgentKind.openaiApi) return OpenAiModels.options(a.endpoint, a.apiKey);
    return _runtimes.of(a.kind)!.loadOptions(a, force: force);
  }

  /// 读取 Agent [a] 的可选项；已读取过且不是 [force] 时直接返回
  Future<void> load(AgentSettings a, {bool force = false}) async {
    if (!supports(a) || _loading.contains(a.uuid)) return;
    if (!force && _options.containsKey(a.uuid)) return;
    _loading.add(a.uuid);
    _errors.remove(a.uuid);
    notifyListeners();
    try {
      _options[a.uuid] = await _read(a, force);
    } catch (e) {
      _errors[a.uuid] = '$e';
    } finally {
      _loading.remove(a.uuid);
      notifyListeners();
    }
  }

  /// 丢弃 Agent [uuid] 的缓存（登录账号变化后，下次使用时重新读取）
  void forget(String uuid) {
    if (_options.remove(uuid) != null || _errors.remove(uuid) != null) notifyListeners();
  }
}
