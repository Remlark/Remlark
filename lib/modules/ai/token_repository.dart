import 'package:drift/drift.dart';

import '../../data/database.dart';
import '../../utils/format_utils.dart';

/// Token 统计汇总
class TokenSummary {
  const TokenSummary(this.input, this.output, this.requests);

  final int input;
  final int output;
  final int requests;

  int get total => input + output;
}

/// 分维度统计行
class TokenGroupRow {
  const TokenGroupRow(this.key, this.summary);

  final String key;
  final TokenSummary summary;
}

/// Token 用量仓库：明细写入，按日期键（索引）范围聚合
class TokenRepository {
  TokenRepository(this._db);

  final AppDatabase _db;

  /// 记录一次请求的用量
  Future<void> record({
    required String agentUuid,
    required String agentName,
    required String model,
    required int input,
    required int output,
  }) async {
    final now = DateTime.now();
    await _db
        .into(_db.tokenUsages)
        .insert(
          TokenUsagesCompanion.insert(
            day: FormatUtils.dayKey(now),
            agentUuid: agentUuid,
            agentName: agentName,
            model: model,
            inputTokens: input,
            outputTokens: output,
            createdAt: now.millisecondsSinceEpoch,
          ),
        );
  }

  Expression<bool> _range(TokenUsages t, DateTime from, DateTime to) =>
      t.day.isBetweenValues(FormatUtils.dayKey(from), FormatUtils.dayKey(to));

  /// 时间范围汇总（day 索引）
  Future<TokenSummary> summary(DateTime from, DateTime to) async {
    final t = _db.tokenUsages;
    final inSum = t.inputTokens.sum();
    final outSum = t.outputTokens.sum();
    final cnt = t.id.count();
    final row =
        await (_db.selectOnly(t)
              ..addColumns([inSum, outSum, cnt])
              ..where(_range(t, from, to)))
            .getSingle();
    return TokenSummary(row.read(inSum) ?? 0, row.read(outSum) ?? 0, row.read(cnt) ?? 0);
  }

  /// 按天聚合（day 索引）
  Future<List<TokenGroupRow>> byDay(DateTime from, DateTime to) => _groupBy(_db.tokenUsages.day, from, to);

  /// 按模型聚合（day+model 复合索引）
  Future<List<TokenGroupRow>> byModel(DateTime from, DateTime to) => _groupBy(_db.tokenUsages.model, from, to);

  /// 按 Agent 聚合（day+agent 复合索引）
  Future<List<TokenGroupRow>> byAgent(DateTime from, DateTime to) => _groupBy(_db.tokenUsages.agentName, from, to);

  Future<List<TokenGroupRow>> _groupBy(GeneratedColumn<String> key, DateTime from, DateTime to) async {
    final t = _db.tokenUsages;
    final inSum = t.inputTokens.sum();
    final outSum = t.outputTokens.sum();
    final cnt = t.id.count();
    final rows =
        await (_db.selectOnly(t)
              ..addColumns([key, inSum, outSum, cnt])
              ..where(_range(t, from, to))
              ..groupBy([key])
              ..orderBy([OrderingTerm.asc(key)]))
            .get();
    return rows
        .map(
          (r) =>
              TokenGroupRow(r.read(key) ?? '', TokenSummary(r.read(inSum) ?? 0, r.read(outSum) ?? 0, r.read(cnt) ?? 0)),
        )
        .toList();
  }
}
