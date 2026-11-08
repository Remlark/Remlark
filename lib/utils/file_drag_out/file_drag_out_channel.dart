import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../app_log.dart';
import 'file_drag_out.dart';

/// 经通道 remlark/file_drag 与原生拖出实现交互，macOS / Windows 共用协议：
/// - start({session: int, entries: [{path, isDir, size}]}) -> bool：Dart 调原生，开始系统拖动
/// - write({session: int, index: int, path: String}) -> null：原生调 Dart，把第 index 项写到本地 path，失败返回错误
/// - ended({session: int})：原生调 Dart，拖动结束（之后仍可能收到 write，放下后才开始写入）
///
/// 各平台只决定交给原生层的条目：macOS 只需顶层项，Windows 需要展开目录中的全部文件
abstract class ChannelFileDragOut extends FileDragOut {
  ChannelFileDragOut({MethodChannel? channel}) : _channel = channel ?? const MethodChannel('remlark/file_drag') {
    _channel.setMethodCallHandler(_handle);
  }

  final MethodChannel _channel;
  int _nextSession = 0;

  /// 最近的拖动会话（条目与取回方法）：放下后系统才请求写入，拖动结束后仍需保留
  final Map<int, (List<DragOutEntry>, DragOutSource)> _sessions = {};

  /// 保留的会话数量上限，更早的会话不再响应写入
  static const _keepSessions = 8;

  @override
  bool get supported => true;

  /// 交给原生层的条目
  @protected
  Future<List<DragOutEntry>> buildEntries(DragOutSource source);

  @override
  Future<bool> start(DragOutSource source) async {
    if (source.items.isEmpty) return false;
    final List<DragOutEntry> entries;
    try {
      entries = await buildEntries(source);
    } catch (e) {
      AppLog.w('drag', '列出拖出文件失败', e);
      return false;
    }
    final session = ++_nextSession;
    _sessions[session] = (entries, source);
    while (_sessions.length > _keepSessions) {
      _sessions.remove(_sessions.keys.first);
    }
    try {
      final ok = await _channel.invokeMethod<bool>('start', {
        'session': session,
        'entries': [for (final e in entries) e.toMap()],
      });
      AppLog.i('drag', '开始拖出 ${entries.length} 项：$ok');
      return ok ?? false;
    } catch (e) {
      AppLog.w('drag', '开始系统拖动失败', e);
      return false;
    }
  }

  /// 处理原生层的回调
  Future<Object?> _handle(MethodCall call) async {
    final args = (call.arguments as Map).cast<String, Object?>();
    final session = args['session'] as int;
    switch (call.method) {
      case 'write':
        final index = args['index'] as int;
        final path = args['path'] as String;
        final s = _sessions[session];
        if (s == null || index < 0 || index >= s.$1.length) {
          throw PlatformException(code: 'expired', message: 'drag session $session expired');
        }
        final (entries, source) = s;
        AppLog.i('drag', '拖出写入 ${entries[index].file.path} → $path');
        try {
          await source.fetch(entries[index].file, path);
        } catch (e) {
          throw PlatformException(code: 'failed', message: '$e');
        }
        return null;
      case 'ended':
        return null;
      default:
        throw MissingPluginException(call.method);
    }
  }
}
