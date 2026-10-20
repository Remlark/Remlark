import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

/// 日志级别
enum LogLevel { debug, info, warn, error }

/// 应用日志：写入 `<数据目录>/logs/remlark-yyyy-MM-dd.log`，按天切分、保留 [keepDays] 天；
/// debug 模式下同时输出到控制台。
///
/// 用法：`AppLog.i('vnc', '连接成功 ...')`。tag 为模块名，便于按模块过滤（如 grep '[vnc]'）。
/// 注意：不要记录密码、私钥、口令等敏感信息。
class AppLog {
  AppLog._();

  /// 日志保留天数
  static const keepDays = 7;

  /// 单条消息最大长度（超出截断，避免大段输出撑爆日志）
  static const maxMessage = 4000;

  static Directory? _dir;
  static IOSink? _sink;
  static String? _sinkDay;

  /// 初始化前产生的日志先缓存，初始化后写入
  static final List<String> _early = [];
  static const _earlyMax = 2000;

  /// 测试或未初始化时是否也输出到控制台
  static bool echo = kDebugMode;

  /// 后台 isolate 中设置：日志行转发给主 isolate（由其调用 [raw] 写入文件）。
  /// 每个 isolate 的静态变量独立，后台 isolate 未初始化日志文件
  static void Function(String line)? forward;

  /// 日志目录（初始化后可用）
  static Directory? get directory => _dir;

  /// 初始化：指定数据目录，清理过期日志，接管未捕获的异常
  static Future<void> init(Directory dataDir) async {
    final dir = Directory(p.join(dataDir.path, 'logs'));
    if (!dir.existsSync()) dir.createSync(recursive: true);
    _dir = dir;
    _cleanup(dir);
    for (final line in _early) {
      _write(line);
    }
    _early.clear();

    // 未捕获的异常也写入日志
    final prevFlutter = FlutterError.onError;
    FlutterError.onError = (details) {
      e('flutter', details.exceptionAsString(), details.exception, details.stack);
      prevFlutter?.call(details);
    };
    final prevPlatform = PlatformDispatcher.instance.onError;
    PlatformDispatcher.instance.onError = (error, stack) {
      e('uncaught', '未捕获的异常', error, stack);
      return prevPlatform?.call(error, stack) ?? false;
    };
    i('app', '日志初始化：${dir.path}，系统 ${Platform.operatingSystem} ${Platform.operatingSystemVersion}');
  }

  static void d(String tag, String msg) => _log(LogLevel.debug, tag, msg);
  static void i(String tag, String msg) => _log(LogLevel.info, tag, msg);
  static void w(String tag, String msg, [Object? error, StackTrace? stack]) => _log(LogLevel.warn, tag, msg, error, stack);
  static void e(String tag, String msg, [Object? error, StackTrace? stack]) =>
      _log(LogLevel.error, tag, msg, error, stack);

  static void _log(LogLevel level, String tag, String msg, [Object? error, StackTrace? stack]) {
    final now = DateTime.now();
    var text = msg.length > maxMessage ? '${msg.substring(0, maxMessage)}…(${msg.length})' : msg;
    if (error != null) text += ' | $error';
    final lvl = switch (level) {
      LogLevel.debug => 'D',
      LogLevel.info => 'I',
      LogLevel.warn => 'W',
      LogLevel.error => 'E',
    };
    final line = '${_time(now)} $lvl [$tag] $text';
    final st = stack?.toString().split('\n').take(12).join('\n');
    final fwd = forward;
    if (fwd != null) {
      fwd(st == null ? line : '$line\n$st');
      return;
    }
    if (echo) debugPrint(line);
    if (_dir == null) {
      // 未初始化（启动早期或测试）时缓存，限制条数避免无限增长
      if (_early.length < _earlyMax) {
        _early.add(line);
        if (st != null) _early.add(st);
      }
      return;
    }
    _write(line);
    if (st != null) _write(st);
  }

  /// 写入其他 isolate 转发来的已格式化日志行
  static void raw(String line) {
    if (echo) debugPrint(line);
    if (_dir == null) {
      if (_early.length < _earlyMax) _early.add(line);
      return;
    }
    _write(line);
  }

  static void _write(String line) {
    try {
      final day = _day(DateTime.now());
      if (_sinkDay != day) {
        _sink?.close();
        _sink = File(p.join(_dir!.path, 'remlark-$day.log')).openWrite(mode: FileMode.append);
        _sinkDay = day;
      }
      _sink!.writeln(line);
    } catch (_) {
      // 写日志失败不影响主流程
    }
  }

  /// 立即落盘（退出或测试时调用）
  static Future<void> flush() async {
    try {
      await _sink?.flush();
    } catch (_) {}
  }

  /// 删除超过保留天数的日志文件
  static void _cleanup(Directory dir) {
    final cutoff = DateTime.now().subtract(const Duration(days: keepDays));
    try {
      for (final f in dir.listSync().whereType<File>()) {
        if (f.path.endsWith('.log') && f.lastModifiedSync().isBefore(cutoff)) f.deleteSync();
      }
    } catch (_) {}
  }

  static String _two(int v) => v.toString().padLeft(2, '0');
  static String _day(DateTime t) => '${t.year}-${_two(t.month)}-${_two(t.day)}';
  static String _time(DateTime t) =>
      '${_day(t)} ${_two(t.hour)}:${_two(t.minute)}:${_two(t.second)}.${t.millisecond.toString().padLeft(3, '0')}';
}
