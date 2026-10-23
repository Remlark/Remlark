import 'package:flutter/foundation.dart';

/// 主导航页
enum AppPage { hosts, sessions, snippets, keys, ai, settings }

/// 设置页分区
enum SettingsSection { general, terminal, remoteDesktop, proxies, sync, agents, data }

/// 主导航控制器（打开会话时自动切换到工作区页）
class NavController extends ChangeNotifier {
  AppPage page = AppPage.hosts;

  /// 设置页当前分区
  SettingsSection settingsSection = SettingsSection.general;

  /// 切换页面
  void go(AppPage p) {
    if (page == p) return;
    page = p;
    notifyListeners();
  }

  /// 打开设置页的指定分区（如从侧栏同步状态跳到同步设置）
  void goSettings(SettingsSection s) {
    page = AppPage.settings;
    settingsSection = s;
    notifyListeners();
  }
}
