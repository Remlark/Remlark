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
  runApp(RemlarkApp(services: services));
}
