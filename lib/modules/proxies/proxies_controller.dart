import 'package:flutter/foundation.dart';

import 'proxy_profile.dart';
import 'proxy_repository.dart';

/// 代理设置与主机选择器共享的状态，不改变当前主机编辑表单。
class ProxiesController extends ChangeNotifier {
  ProxiesController(this.repository);

  final ProxyRepository repository;
  List<ProxyEntry> entries = [];
  Map<String, int> usage = {};
  Future<void> Function()? onChanged;

  /// 重新读取配置和引用数量。
  Future<void> load() async {
    entries = await repository.list();
    usage = await repository.usageCounts();
    notifyListeners();
  }

  /// 保存后刷新主机列表，使新建会话及可移植快照使用新参数。
  Future<void> save(ProxyEntry entry) async {
    await repository.save(entry);
    await onChanged?.call();
    await load();
  }

  /// 删除前由仓库原子校验是否有引用。
  Future<bool> delete(String uuid) async {
    final deleted = await repository.delete(uuid);
    await load();
    return deleted;
  }
}
