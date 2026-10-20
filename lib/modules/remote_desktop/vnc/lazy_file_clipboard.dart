import 'dart:io';

import 'package:flutter/services.dart';

import '../../../utils/app_log.dart';

/// 延迟提供文件的本地剪贴板：远程复制文件时只放入占位项，本地粘贴时才回调 [onProvide] 下载。
/// 跨平台接口：macOS 由原生 NSPasteboardItemDataProvider 实现；其他平台不支持（[supported] 为 false），
/// 调用方回退为复制时立即下载
abstract class LazyFileClipboard {
  /// 当前平台的实现
  static final LazyFileClipboard instance = Platform.isMacOS
      ? _MacLazyFileClipboard()
      : _UnsupportedLazyFileClipboard();

  /// 是否支持延迟提供
  bool get supported;

  /// 粘贴时请求文件：参数为 [offer] 时传入的标识，返回下载后的本地路径（失败返回 null）
  Future<String?> Function(String id)? onProvide;

  /// 放入占位项（每个标识一个文件），成功返回 true
  Future<bool> offer(List<String> ids);

  /// 剪贴板当前内容是否为本程序放入的占位项（读取占位项的文件会触发下载，检查本地剪贴板前需先判断）
  Future<bool> ownsClipboard();
}

/// macOS：经通道 remlark/lazy_pasteboard 与原生 LazyFilePasteboard 交互
class _MacLazyFileClipboard extends LazyFileClipboard {
  _MacLazyFileClipboard() {
    _channel.setMethodCallHandler((call) async {
      if (call.method != 'provide') throw MissingPluginException(call.method);
      final id = call.arguments as String;
      final cb = onProvide;
      if (cb == null) return null;
      return cb(id);
    });
  }

  static const _channel = MethodChannel('remlark/lazy_pasteboard');

  @override
  bool get supported => true;

  @override
  Future<bool> offer(List<String> ids) async {
    try {
      final cc = await _channel.invokeMethod<int>('offer', {'ids': ids});
      return cc != null;
    } catch (e) {
      AppLog.w('clipboard', '放入延迟文件占位项失败', e);
      return false;
    }
  }

  @override
  Future<bool> ownsClipboard() async {
    try {
      return await _channel.invokeMethod<bool>('ownsClipboard') ?? false;
    } catch (_) {
      return false;
    }
  }
}

/// 其他平台：不支持延迟提供
class _UnsupportedLazyFileClipboard extends LazyFileClipboard {
  @override
  bool get supported => false;

  @override
  Future<bool> offer(List<String> ids) async => false;

  @override
  Future<bool> ownsClipboard() async => false;
}
