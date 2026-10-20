import 'dart:ui' show AppExitResponse;

import 'package:flutter/material.dart';

import 'app/app.dart';
import 'app/app_services.dart';
import 'data/database.dart';
import 'utils/app_log.dart';
import 'utils/platform_utils.dart';
import 'utils/secret_store.dart';

/// 程序入口：初始化主密钥、数据库与服务后启动界面
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await AppLog.init(await PlatformUtils.dataDir());
  await SecretStore.init();
  final services = AppServices(AppDatabase());
  await services.init(
    installKeySnippetName: services.settings.locale.languageCode == 'zh' ? '系统免密登录' : 'Install system SSH key',
  );
  // 退出（Dock 退出、⌘Q、关闭最后一个窗口）前先释放资源并关闭数据库，再允许退出。
  // 监听器创建时即注册到 WidgetsBinding，由它持有，无需保存引用
  AppLifecycleListener(
    onExitRequested: () async {
      await services.shutdown();
      return AppExitResponse.exit;
    },
  );
  runApp(RemlarkApp(services: services));
}
