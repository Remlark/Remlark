import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../app/app_services.dart';
import '../../../l10n/app_localizations.dart';
import '../../../utils/format_utils.dart';
import '../token_repository.dart';

/// 统计时间范围
enum StatsRange { today, week, month }

/// Token 统计：今日 / 本周 / 本月汇总，按天柱状图，按模型、按 Agent 明细
class TokenStatsView extends StatefulWidget {
  const TokenStatsView({super.key});

  @override
  State<TokenStatsView> createState() => _TokenStatsViewState();
}

class _TokenStatsViewState extends State<TokenStatsView> {
  StatsRange _range = StatsRange.week;
  TokenSummary? _today, _week, _month;
  List<TokenGroupRow> _days = [], _models = [], _agents = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  (DateTime, DateTime) _bounds(StatsRange r) {
    final now = DateTime.now();
    return switch (r) {
      StatsRange.today => (now, now),
      StatsRange.week => (FormatUtils.startOfWeek(now), now),
      StatsRange.month => (FormatUtils.startOfMonth(now), now),
    };
  }

  Future<void> _load() async {
    final repo = context.read<AppServices>().tokenRepo;
    final now = DateTime.now();
    final t = await repo.summary(now, now);
    final w = await repo.summary(FormatUtils.startOfWeek(now), now);
    final m = await repo.summary(FormatUtils.startOfMonth(now), now);
    final (from, to) = _bounds(_range);
    // 柱状图固定展示最近 30 天
    final days = await repo.byDay(now.subtract(const Duration(days: 29)), now);
    final models = await repo.byModel(from, to);
    final agents = await repo.byAgent(from, to);
    if (!mounted) return;
    setState(() {
      _today = t;
      _week = w;
      _month = m;
      _days = days;
      _models = models;
      _agents = agents;
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        Row(
          children: [
            Expanded(
              child: _SummaryCard(title: context.tr('stats.today'), s: _today),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _SummaryCard(title: context.tr('stats.week'), s: _week),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _SummaryCard(title: context.tr('stats.month'), s: _month),
            ),
          ],
        ),
        const SizedBox(height: 20),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(context.tr('stats.daily'), style: theme.textTheme.titleSmall),
                const SizedBox(height: 12),
                SizedBox(height: 220, child: _DailyChart(rows: _days)),
              ],
            ),
          ),
        ),
        const SizedBox(height: 20),
        Row(
          children: [
            Text(context.tr('stats.breakdown'), style: theme.textTheme.titleSmall),
            const Spacer(),
            SegmentedButton<StatsRange>(
              showSelectedIcon: false,
              segments: [
                ButtonSegment(value: StatsRange.today, label: Text(context.tr('stats.today'))),
                ButtonSegment(value: StatsRange.week, label: Text(context.tr('stats.week'))),
                ButtonSegment(value: StatsRange.month, label: Text(context.tr('stats.month'))),
              ],
              selected: {_range},
              onSelectionChanged: (s) {
                setState(() => _range = s.first);
                _load();
              },
            ),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: _GroupTable(title: context.tr('stats.by_model'), rows: _models),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _GroupTable(title: context.tr('stats.by_agent'), rows: _agents),
            ),
          ],
        ),
      ],
    );
  }
}

class _SummaryCard extends StatelessWidget {
  const _SummaryCard({required this.title, required this.s});

  final String title;
  final TokenSummary? s;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final v = s;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: theme.textTheme.labelLarge?.copyWith(color: theme.colorScheme.outline)),
            const SizedBox(height: 6),
            Text(
              v == null ? '-' : FormatUtils.tokens(v.total),
              style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 4),
            Text(
              v == null
                  ? ''
                  : '↑ ${FormatUtils.tokens(v.input)}   ↓ ${FormatUtils.tokens(v.output)}   ·  ${context.tr('stats.requests', {'n': v.requests})}',
              style: theme.textTheme.bodySmall,
            ),
          ],
        ),
      ),
    );
  }
}

class _DailyChart extends StatelessWidget {
  const _DailyChart({required this.rows});

  final List<TokenGroupRow> rows;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final now = DateTime.now();
    final byDay = {for (final r in rows) r.key: r.summary};
    final days = [for (var i = 29; i >= 0; i--) FormatUtils.dayKey(now.subtract(Duration(days: i)))];
    final maxY = days.map((d) => byDay[d]?.total ?? 0).fold<int>(0, (a, b) => a > b ? a : b);
    return BarChart(
      BarChartData(
        maxY: maxY == 0 ? 10 : maxY * 1.15,
        gridData: const FlGridData(drawVerticalLine: false),
        borderData: FlBorderData(show: false),
        barTouchData: BarTouchData(
          touchTooltipData: BarTouchTooltipData(
            getTooltipItem: (group, _, rod, _) {
              final s = byDay[days[group.x]];
              return BarTooltipItem(
                '${days[group.x]}\n↑${FormatUtils.tokens(s?.input ?? 0)} ↓${FormatUtils.tokens(s?.output ?? 0)}',
                const TextStyle(color: Colors.white, fontSize: 11),
              );
            },
          ),
        ),
        titlesData: FlTitlesData(
          topTitles: const AxisTitles(),
          rightTitles: const AxisTitles(),
          leftTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 44,
              getTitlesWidget: (v, _) => Text(FormatUtils.tokens(v.toInt()), style: const TextStyle(fontSize: 10)),
            ),
          ),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              getTitlesWidget: (v, _) {
                final i = v.toInt();
                if (i % 5 != 4) return const SizedBox.shrink();
                return Text(days[i].substring(5), style: const TextStyle(fontSize: 10));
              },
            ),
          ),
        ),
        barGroups: [
          for (var i = 0; i < days.length; i++)
            BarChartGroupData(
              x: i,
              barRods: [
                BarChartRodData(
                  toY: (byDay[days[i]]?.total ?? 0).toDouble(),
                  width: 10,
                  borderRadius: BorderRadius.circular(3),
                  rodStackItems: byDay[days[i]] == null
                      ? []
                      : [
                          BarChartRodStackItem(0, byDay[days[i]]!.input.toDouble(), scheme.primary),
                          BarChartRodStackItem(
                            byDay[days[i]]!.input.toDouble(),
                            byDay[days[i]]!.total.toDouble(),
                            scheme.tertiary,
                          ),
                        ],
                  color: scheme.primary,
                ),
              ],
            ),
        ],
      ),
    );
  }
}

class _GroupTable extends StatelessWidget {
  const _GroupTable({required this.title, required this.rows});

  final String title;
  final List<TokenGroupRow> rows;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: theme.textTheme.titleSmall),
            const SizedBox(height: 8),
            if (rows.isEmpty) Text(context.tr('stats.empty'), style: theme.textTheme.bodySmall),
            if (rows.isNotEmpty)
              Table(
                columnWidths: const {0: FlexColumnWidth(2)},
                children: [
                  TableRow(
                    children: [
                      for (final h in ['', 'stats.input', 'stats.output', 'stats.total'])
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 4),
                          child: Text(h.isEmpty ? '' : context.tr(h), style: theme.textTheme.labelSmall),
                        ),
                    ],
                  ),
                  for (final r in rows)
                    TableRow(
                      children: [
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 4),
                          child: Text(r.key, overflow: TextOverflow.ellipsis),
                        ),
                        Text(FormatUtils.tokens(r.summary.input)),
                        Text(FormatUtils.tokens(r.summary.output)),
                        Text(FormatUtils.tokens(r.summary.total), style: const TextStyle(fontWeight: FontWeight.w600)),
                      ],
                    ),
                ],
              ),
          ],
        ),
      ),
    );
  }
}
