import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../app/nav_controller.dart';
import '../../../app/theme/app_theme.dart';
import '../../../l10n/app_localizations.dart';
import '../../../ui_kit/page_header.dart';
import 'chat_history_view.dart';
import 'token_stats_view.dart';

/// AI 页面：Token 统计与聊天记录。每次进入页面时重建子视图以刷新数据
class AiPage extends StatefulWidget {
  const AiPage({super.key});

  @override
  State<AiPage> createState() => _AiPageState();
}

class _AiPageState extends State<AiPage> {
  int _generation = 0;
  AppPage? _lastPage;

  @override
  Widget build(BuildContext context) {
    final page = context.watch<NavController>().page;
    if (page == AppPage.ai && _lastPage != AppPage.ai) _generation++;
    _lastPage = page;
    return DefaultTabController(
      length: 2,
      child: PageFrame(
        header: PageHeader(title: context.tr('nav.ai'), subtitle: context.tr('ai.page.subtitle')),
        headerBottom: Padding(
          padding: const EdgeInsets.only(left: AppSizes.pagePadding - 12),
          child: TabBar(
            isScrollable: true,
            tabAlignment: TabAlignment.start,
            labelPadding: const EdgeInsets.symmetric(horizontal: 12),
            tabs: [
              Tab(height: 42, text: context.tr('ai.tab.stats')),
              Tab(height: 42, text: context.tr('ai.tab.history')),
            ],
          ),
        ),
        body: TabBarView(key: ValueKey(_generation), children: const [TokenStatsView(), ChatHistoryView()]),
      ),
    );
  }
}
