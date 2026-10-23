import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:provider/provider.dart';

import '../l10n/app_localizations.dart';
import '../utils/ui_utils.dart';
import 'app_services.dart';
import 'shell/home_shell.dart';
import 'nav_controller.dart';
import 'theme/app_palette.dart';
import 'theme/app_theme.dart';

/// 应用根组件：注入依赖、配置主题与多语言
class RemlarkApp extends StatelessWidget {
  const RemlarkApp({super.key, required this.services});

  final AppServices services;

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        Provider.value(value: services),
        ChangeNotifierProvider.value(value: services.settings),
        ChangeNotifierProvider.value(value: services.hosts),
        ChangeNotifierProvider.value(value: services.proxies),
        ChangeNotifierProvider.value(value: services.workspace),
        ChangeNotifierProvider.value(value: services.sync),
        ChangeNotifierProvider.value(value: services.agents),
        Provider.value(value: services.runtimes),
        ChangeNotifierProvider.value(value: services.agentOptions),
        ChangeNotifierProvider(create: (_) => NavController()),
      ],
      child: Builder(
        builder: (context) {
          final settings = context.watch<AppServices>().settings;
          return ListenableBuilder(
            listenable: settings,
            builder: (context, _) => MaterialApp(
              title: 'Remlark',
              debugShowCheckedModeBanner: false,
              navigatorKey: UiUtils.navigatorKey,
              scaffoldMessengerKey: UiUtils.messengerKey,
              theme: AppTheme.build(Brightness.light, AccentPreset.byId(settings.accent)),
              darkTheme: AppTheme.build(Brightness.dark, AccentPreset.byId(settings.accent)),
              themeMode: settings.themeMode,
              locale: settings.locale,
              supportedLocales: S.supportedLocales,
              localizationsDelegates: const [
                S.delegate,
                GlobalMaterialLocalizations.delegate,
                GlobalWidgetsLocalizations.delegate,
                GlobalCupertinoLocalizations.delegate,
              ],
              home: const HomeShell(),
            ),
          );
        },
      ),
    );
  }
}
