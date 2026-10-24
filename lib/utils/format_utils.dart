/// 格式化工具：文件大小、时间、日期键、速率等
class FormatUtils {
  FormatUtils._();

  /// 字节数转可读字符串
  static String bytes(num value) {
    const units = ['B', 'KB', 'MB', 'GB', 'TB'];
    var v = value.toDouble();
    var i = 0;
    while (v >= 1024 && i < units.length - 1) {
      v /= 1024;
      i++;
    }
    return i == 0
        ? '${v.toInt()} ${units[i]}'
        : '${v.toStringAsFixed(1)} ${units[i]}';
  }

  /// 每秒字节数
  static String speed(num bytesPerSecond) => '${bytes(bytesPerSecond)}/s';

  /// 两位补零
  static String _two(int v) => v.toString().padLeft(2, '0');

  /// yyyy-MM-dd HH:mm 格式
  static String dateTime(DateTime t) {
    final l = t.toLocal();
    return '${l.year}-${_two(l.month)}-${_two(l.day)} ${_two(l.hour)}:${_two(l.minute)}';
  }

  /// 最近时间使用本地化相对文案，超过一周保留完整时间；未来时间按刚刚处理。
  static String relativeDateTime(
    DateTime value,
    String Function(String, [Map<String, Object?>]) translate, {
    DateTime? now,
  }) {
    final elapsed = (now ?? DateTime.now()).difference(value);
    if (elapsed.inMinutes < 1) return translate('time.just_now');
    if (elapsed.inHours < 1) {
      return translate('time.minutes_ago', {'n': elapsed.inMinutes});
    }
    if (elapsed.inDays < 1) {
      return translate('time.hours_ago', {'n': elapsed.inHours});
    }
    if (elapsed.inDays < 7) {
      return translate('time.days_ago', {'n': elapsed.inDays});
    }
    return dateTime(value);
  }

  /// yyyy-MM-dd 格式，同时作为 Token 统计的“日期键”
  static String dayKey(DateTime t) {
    final l = t.toLocal();
    return '${l.year}-${_two(l.month)}-${_two(l.day)}';
  }

  /// 从 Unix 秒时间戳格式化
  static String unixTime(int? seconds) {
    if (seconds == null) return '';
    return dateTime(DateTime.fromMillisecondsSinceEpoch(seconds * 1000));
  }

  /// Token 数量缩写：1234 -> 1.2K
  static String tokens(int v) {
    if (v >= 1000000) return '${(v / 1000000).toStringAsFixed(2)}M';
    if (v >= 1000) return '${(v / 1000).toStringAsFixed(1)}K';
    return '$v';
  }

  /// 时长：HH:mm:ss
  static String duration(Duration d) {
    final s = d.inSeconds < 0 ? 0 : d.inSeconds;
    return '${_two(s ~/ 3600)}:${_two(s % 3600 ~/ 60)}:${_two(s % 60)}';
  }

  /// 本周一 0 点
  static DateTime startOfWeek(DateTime t) {
    final d = DateTime(t.year, t.month, t.day);
    return d.subtract(Duration(days: d.weekday - 1));
  }

  /// 本月 1 日 0 点
  static DateTime startOfMonth(DateTime t) => DateTime(t.year, t.month, 1);
}
