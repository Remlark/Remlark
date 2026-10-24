import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:remlark/l10n/app_localizations.dart';
import 'package:remlark/utils/format_utils.dart';

/// 验证相对时间的中英文、未来时间保护和跨周完整日期回退。
void main() {
  test('最近连接时间不会出现负数，旧记录保留精确时间', () {
    final now = DateTime(2026, 10, 24, 12);
    final zh = S(const Locale('zh'));
    final en = S(const Locale('en'));
    expect(
      FormatUtils.relativeDateTime(
        now.add(const Duration(minutes: 5)),
        zh.t,
        now: now,
      ),
      '刚刚',
    );
    expect(
      FormatUtils.relativeDateTime(
        now.subtract(const Duration(minutes: 59)),
        en.t,
        now: now,
      ),
      '59 min ago',
    );
    expect(
      FormatUtils.relativeDateTime(
        now.subtract(const Duration(hours: 1)),
        zh.t,
        now: now,
      ),
      '1 小时前',
    );
    expect(
      FormatUtils.relativeDateTime(
        now.subtract(const Duration(days: 1)),
        en.t,
        now: now,
      ),
      '1d ago',
    );
    final old = now.subtract(const Duration(days: 7));
    expect(
      FormatUtils.relativeDateTime(old, zh.t, now: now),
      '2026-10-17 12:00',
    );
  });
}
