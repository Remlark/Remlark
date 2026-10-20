import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../app/app_services.dart';
import '../../../app/theme/app_palette.dart';
import '../../../app/theme/app_theme.dart';
import '../../../l10n/app_localizations.dart';
import '../../../ui_kit/app_table.dart';
import '../../../ui_kit/buttons.dart';
import '../../../ui_kit/panel.dart';
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
    final p = context.palette;
    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        LayoutBuilder(
          builder: (context, box) {
            final cards = [
              _SummaryCard(title: context.tr('stats.today'), s: _today),
              _SummaryCard(title: context.tr('stats.week'), s: _week),
              _SummaryCard(title: context.tr('stats.month'), s: _month),
            ];
            return Row(
              children: [
                for (var i = 0; i < cards.length; i++) ...[
                  if (i > 0) const SizedBox(width: 16),
                  Expanded(child: cards[i]),
                ],
              ],
            );
          },
        ),
        const SizedBox(height: 16),
        AppPanel(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      context.tr('stats.daily'),
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: p.text),
                    ),
                  ),
                  _Legend(color: p.textFaint, text: context.tr('stats.input_token')),
                  const SizedBox(width: 16),
                  _Legend(color: p.accent, text: context.tr('stats.output_token')),
                ],
              ),
              const SizedBox(height: 16),
              SizedBox(height: 220, child: _DailyChart(rows: _days)),
            ],
          ),
        ),
        const SizedBox(height: 20),
        Row(
          children: [
            Text(
              context.tr('stats.breakdown'),
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: p.text),
            ),
            const Spacer(),
            PillChoice<StatsRange>(
              compact: true,
              items: [
                (StatsRange.today, context.tr('stats.today')),
                (StatsRange.week, context.tr('stats.week')),
                (StatsRange.month, context.tr('stats.month')),
              ],
              value: _range,
              onChanged: (v) {
                setState(() => _range = v);
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
              child: _GroupTable(
                title: context.tr('stats.by_model'),
                keyLabel: context.tr('stats.model'),
                rows: _models,
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: _GroupTable(title: context.tr('stats.by_agent'), keyLabel: 'Agent', rows: _agents),
            ),
          ],
        ),
      ],
    );
  }
}

/// 图例
class _Legend extends StatelessWidget {
  const _Legend({required this.color, required this.text});

  final Color color;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 9,
          height: 9,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 6),
        Text(text, style: TextStyle(fontSize: 13, color: context.palette.textMuted)),
      ],
    );
  }
}

/// 汇总卡片：图标、总量，以及输入 / 输出 / 请求次数
class _SummaryCard extends StatelessWidget {
  const _SummaryCard({required this.title, required this.s});

  final String title;
  final TokenSummary? s;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final v = s;
    Widget stat(String label, String value) => Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 12.5, color: p.textMuted),
          ),
          const SizedBox(height: 4),
          Text(
            value,
            maxLines: 1,
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: p.text),
          ),
        ],
      ),
    );
    return AppPanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 46,
                height: 46,
                decoration: BoxDecoration(
                  color: p.accentSoft,
                  borderRadius: BorderRadius.circular(AppSizes.radius + 4),
                ),
                child: Icon(Icons.calendar_today_outlined, size: 20, color: p.accent),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: TextStyle(fontSize: 13, color: p.textMuted)),
                    Text(
                      v == null ? '-' : FormatUtils.tokens(v.total),
                      maxLines: 1,
                      style: TextStyle(fontSize: 28, fontWeight: FontWeight.w700, color: p.text, height: 1.2),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              stat(context.tr('stats.input_token'), v == null ? '-' : FormatUtils.tokens(v.input)),
              stat(context.tr('stats.output_token'), v == null ? '-' : FormatUtils.tokens(v.output)),
              stat(context.tr('stats.request_count'), v == null ? '-' : '${v.requests}'),
            ],
          ),
        ],
      ),
    );
  }
}

class _DailyChart extends StatelessWidget {
  const _DailyChart({required this.rows});

  final List<TokenGroupRow> rows;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final now = DateTime.now();
    final byDay = {for (final r in rows) r.key: r.summary};
    final days = [for (var i = 29; i >= 0; i--) FormatUtils.dayKey(now.subtract(Duration(days: i)))];
    final maxY = days.map((d) => byDay[d]?.total ?? 0).fold<int>(0, (a, b) => a > b ? a : b);
    return BarChart(
      BarChartData(
        maxY: maxY == 0 ? 10 : maxY * 1.15,
        gridData: FlGridData(
          drawVerticalLine: false,
          getDrawingHorizontalLine: (_) => FlLine(color: p.border, strokeWidth: 1, dashArray: [4, 4]),
        ),
        borderData: FlBorderData(show: false),
        barTouchData: BarTouchData(
          touchTooltipData: BarTouchTooltipData(
            getTooltipItem: (group, _, rod, _) {
              final s = byDay[days[group.x]];
              return BarTooltipItem(
                '${days[group.x]}\n↑${FormatUtils.tokens(s?.input ?? 0)} ↓${FormatUtils.tokens(s?.output ?? 0)}',
                TextStyle(color: p.text, fontSize: 11),
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
              getTitlesWidget: (v, _) =>
                  Text(FormatUtils.tokens(v.toInt()), style: TextStyle(fontSize: 11, color: p.textMuted)),
            ),
          ),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              getTitlesWidget: (v, _) {
                final i = v.toInt();
                if (i % 5 != 4) return const SizedBox.shrink();
                return Text(days[i].substring(5), style: TextStyle(fontSize: 11, color: p.textMuted));
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
                  width: 12,
                  borderRadius: BorderRadius.circular(3),
                  rodStackItems: byDay[days[i]] == null
                      ? []
                      : [
                          BarChartRodStackItem(0, byDay[days[i]]!.input.toDouble(), p.textFaint),
                          BarChartRodStackItem(
                            byDay[days[i]]!.input.toDouble(),
                            byDay[days[i]]!.total.toDouble(),
                            p.accent,
                          ),
                        ],
                  color: p.accent,
                ),
              ],
            ),
        ],
      ),
    );
  }
}

/// 分维度明细表：名称、输入、输出、合计、请求次数，末行为总计
class _GroupTable extends StatelessWidget {
  const _GroupTable({required this.title, required this.keyLabel, required this.rows});

  final String title;
  final String keyLabel;
  final List<TokenGroupRow> rows;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final cols = [
      AppColumn(keyLabel, flex: 3),
      AppColumn(context.tr('stats.input'), flex: 2, alignEnd: true),
      AppColumn(context.tr('stats.output'), flex: 2, alignEnd: true),
      AppColumn(context.tr('stats.total'), flex: 2, alignEnd: true),
      AppColumn(context.tr('stats.request_count'), flex: 2, alignEnd: true),
    ];
    final sum = rows.fold<(int, int, int)>((
      0,
      0,
      0,
    ), (a, r) => (a.$1 + r.summary.input, a.$2 + r.summary.output, a.$3 + r.summary.requests));
    final bold = TextStyle(fontWeight: FontWeight.w700, color: p.text);
    List<Widget> cells(String k, int i, int o, int n, {bool strong = false}) => [
      Text(k, maxLines: 1, overflow: TextOverflow.ellipsis, style: strong ? bold : null),
      Text(FormatUtils.tokens(i), style: strong ? bold : TextStyle(color: p.textMuted)),
      Text(FormatUtils.tokens(o), style: strong ? bold : TextStyle(color: p.textMuted)),
      Text(FormatUtils.tokens(i + o), style: bold),
      Text('$n', style: strong ? bold : TextStyle(color: p.textMuted)),
    ];
    return AppPanel(
      padding: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
            child: Text(
              title,
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: p.text),
            ),
          ),
          Container(height: 1, color: p.border),
          AppTableHeader(columns: cols, padding: 12),
          if (rows.isEmpty)
            Padding(
              padding: const EdgeInsets.all(20),
              child: Text(context.tr('stats.empty'), style: TextStyle(color: p.textFaint)),
            ),
          for (final r in rows)
            AppTableRow(
              columns: cols,
              height: 44,
              cells: cells(r.key, r.summary.input, r.summary.output, r.summary.requests),
            ),
          if (rows.isNotEmpty)
            AppTableRow(
              columns: cols,
              height: 44,
              divider: false,
              cells: cells(context.tr('stats.sum'), sum.$1, sum.$2, sum.$3, strong: true),
            ),
        ],
      ),
    );
  }
}
