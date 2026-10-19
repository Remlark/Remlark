import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../app/nav_controller.dart';
import '../../../l10n/app_localizations.dart';
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
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 12, 24, 0),
            child: Row(
              children: [
                Text(context.tr('nav.ai'), style: Theme.of(context).textTheme.titleLarge),
                const SizedBox(width: 24),
                Expanded(
                  child: TabBar(
                    isScrollable: true,
                    tabAlignment: TabAlignment.start,
                    tabs: [
                      Tab(text: context.tr('ai.tab.stats')),
                      Tab(text: context.tr('ai.tab.history')),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: TabBarView(key: ValueKey(_generation), children: const [TokenStatsView(), ChatHistoryView()]),
          ),
        ],
      ),
    );
  }
}
