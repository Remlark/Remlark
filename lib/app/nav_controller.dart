import 'package:flutter/foundation.dart';

/// 主导航页
enum AppPage { hosts, sessions, snippets, keys, ai, settings }

/// 主导航控制器（打开会话时自动切换到会话页）
class NavController extends ChangeNotifier {
  AppPage page = AppPage.hosts;

  void go(AppPage p) {
    if (page == p) return;
    page = p;
    notifyListeners();
  }
}
