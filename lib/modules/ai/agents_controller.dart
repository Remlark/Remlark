import 'package:flutter/foundation.dart';

import 'agent_config.dart';
import 'agent_repository.dart';

/// Agent 配置控制器：列表、当前 Agent 切换
class AgentsController extends ChangeNotifier {
  AgentsController(this._repo);

  final AgentRepository _repo;
  List<AgentSettings> agents = [];

  /// 当前使用的 Agent
  AgentSettings? get active {
    for (final a in agents) {
      if (a.isActive) return a;
    }
    return agents.isEmpty ? null : agents.first;
  }

  Future<void> load() async {
    agents = await _repo.list();
    notifyListeners();
  }

  Future<void> save(AgentSettings a) async {
    await _repo.save(a);
    if (agents.isEmpty || a.isActive) await _repo.setActive(a.uuid);
    await load();
  }

  Future<void> setActive(String uuid) async {
    await _repo.setActive(uuid);
    await load();
  }

  Future<void> delete(String uuid) async {
    await _repo.delete(uuid);
    await load();
  }
}
