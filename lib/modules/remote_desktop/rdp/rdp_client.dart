import 'dart:ffi';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';

import 'rdp_bindings.dart';

/// 原生事件类型（与 native/rdp/src/remlark_rdp.h 保持一致）
class RdpEvent {
  RdpEvent._();

  static const connected = 1;
  static const frame = 2;
  static const resize = 3;
  static const disconnected = 4;
  static const authFailed = 5;
  static const certificate = 6;
  static const clipText = 7;
  static const clipFiles = 8;
  static const clipFilesSkipped = 9;
  static const clipFilesProgress = 10;
}

/// RDP 鼠标标志位
class RdpPointer {
  RdpPointer._();

  static const wheelNegative = 0x0100;
  static const wheel = 0x0200;
  static const hWheel = 0x0400;
  static const move = 0x0800;
  static const button1 = 0x1000;
  static const button2 = 0x2000;
  static const button3 = 0x4000;
  static const down = 0x8000;
}

/// 连接参数
class RdpConnectOptions {
  const RdpConnectOptions({
    required this.host,
    required this.port,
    this.username = '',
    this.password = '',
    this.domain = '',
    required this.width,
    required this.height,
    this.sharedDir,
    this.clipboard = true,
    this.knownFingerprint,
    this.tempDir,
    this.proxyType = 0,
    this.proxyHost = '',
    this.proxyPort = 0,
    this.proxyUser = '',
    this.proxyPassword = '',
  });

  final String host;
  final int port;
  final String username;
  final String password;
  final String domain;
  final int width;
  final int height;
  final String? sharedDir;
  final bool clipboard;
  final String? knownFingerprint;
  final String? tempDir;

  /// 出口代理：0 不使用 / 1 HTTP / 2 SOCKS5
  final int proxyType;
  final String proxyHost;
  final int proxyPort;
  final String proxyUser;
  final String proxyPassword;
}

/// 原生库不可用
class RdpLibraryMissing implements Exception {
  @override
  String toString() => 'RDP native library missing';
}

/// RDP 客户端：封装 FreeRDP 胶水库，事件以回调形式通知
class RdpClient {
  RdpClient() : _id = _nextId++ {
    _handle = rmk_rdp_new(_id, _callback.nativeFunction);
    _clients[_id] = this;
  }

  static int _nextId = 1;
  static final Map<int, RdpClient> _clients = {};

  /// 所有实例共享的原生回调（可从任意线程调用，消息投递到 Dart 事件循环）
  static final NativeCallable<RmkEventCallbackNative> _callback = NativeCallable<RmkEventCallbackNative>.listener(
    _dispatch,
  );

  static bool? _available;

  /// 原生库是否可用
  static bool get isAvailable {
    if (_available != null) return _available!;
    try {
      rmk_rdp_version();
      _available = true;
    } catch (_) {
      _available = false;
    }
    return _available!;
  }

  /// FreeRDP 版本
  static String get version => isAvailable ? rmk_rdp_version().toDartString() : '';

  final int _id;
  late Pointer<RmkRdp> _handle;
  Pointer<Uint8> _buffer = nullptr;
  int _bufferSize = 0;
  bool _disposed = false;

  int width = 0;
  int height = 0;

  void Function(int width, int height)? onConnected;
  void Function()? onFrame;
  void Function(int width, int height)? onResize;
  void Function(int code, String? message)? onDisconnected;
  void Function(String? message)? onAuthFailed;

  /// 证书：changed 为 true 表示指纹与记录不一致（连接已被拒绝）
  void Function(bool changed, String fingerprint)? onCertificate;
  void Function(String text)? onClipboardText;
  void Function(List<String> paths)? onClipboardFiles;
  void Function(int count, int megabytes)? onClipboardFilesSkipped;
  void Function(int doneKb, int totalKb)? onClipboardFilesProgress;

  /// 分发原生事件
  static void _dispatch(int id, int type, int a, int b, int c, int d, Pointer<Utf8> str) {
    String? s;
    if (str != nullptr) {
      s = str.toDartString();
      rmk_rdp_free_string(str);
    }
    final client = _clients[id];
    if (client == null || client._disposed) return;
    switch (type) {
      case RdpEvent.connected:
        client
          ..width = a
          ..height = b;
        client.onConnected?.call(a, b);
      case RdpEvent.frame:
        client.onFrame?.call();
      case RdpEvent.resize:
        client
          ..width = a
          ..height = b;
        client.onResize?.call(a, b);
      case RdpEvent.disconnected:
        client.onDisconnected?.call(a, s);
      case RdpEvent.authFailed:
        client.onAuthFailed?.call(s);
      case RdpEvent.certificate:
        client.onCertificate?.call(a == 1, s ?? '');
      case RdpEvent.clipText:
        if (s != null) client.onClipboardText?.call(s);
      case RdpEvent.clipFiles:
        if (s != null) client.onClipboardFiles?.call(s.split('\n'));
      case RdpEvent.clipFilesSkipped:
        client.onClipboardFilesSkipped?.call(a, b);
      case RdpEvent.clipFilesProgress:
        client.onClipboardFilesProgress?.call(a, b);
    }
  }

  /// 开始连接（异步，结果通过回调通知）
  void connect(RdpConnectOptions o) {
    using((arena) {
      Pointer<Utf8> s(String? v) => v == null || v.isEmpty ? nullptr : v.toNativeUtf8(allocator: arena);
      rmk_rdp_set_proxy(_handle, o.proxyType, s(o.proxyHost), o.proxyPort, s(o.proxyUser), s(o.proxyPassword));
      final rc = rmk_rdp_connect(
        _handle,
        s(o.host),
        o.port,
        s(o.username),
        s(o.password),
        s(o.domain),
        o.width,
        o.height,
        s(o.sharedDir),
        o.clipboard ? 1 : 0,
        s(o.knownFingerprint),
        s(o.tempDir),
      );
      if (rc != 0) throw StateError('rdp connect failed: $rc');
    });
  }

  /// 拷贝当前画面（BGRA），无画面时返回 null
  Uint8List? copyFrame() {
    if (_disposed) return null;
    return using((arena) {
      final w = arena<Int32>();
      final h = arena<Int32>();
      var n = rmk_rdp_copy_frame(_handle, _buffer, _bufferSize, w, h);
      if (n < 0) {
        // 缓冲区不足，按所需大小重新分配
        if (_buffer != nullptr) malloc.free(_buffer);
        _bufferSize = -n;
        _buffer = malloc<Uint8>(_bufferSize);
        n = rmk_rdp_copy_frame(_handle, _buffer, _bufferSize, w, h);
      }
      if (n <= 0) return null;
      width = w.value;
      height = h.value;
      return Uint8List.fromList(_buffer.asTypedList(n));
    });
  }

  /// 键盘扫描码（扩展键 | 0x100）
  void sendKey(int scancode, bool down, {bool repeat = false}) {
    if (!_disposed) rmk_rdp_send_key(_handle, scancode, down ? 1 : 0, repeat ? 1 : 0);
  }

  /// Unicode 字符
  void sendUnicode(int codepoint, bool down) {
    if (!_disposed) rmk_rdp_send_unicode(_handle, codepoint, down ? 1 : 0);
  }

  /// 鼠标事件
  void sendMouse(int flags, int x, int y) {
    if (!_disposed) rmk_rdp_send_mouse(_handle, flags, x, y);
  }

  /// 请求调整远程分辨率
  void resize(int w, int h) {
    if (!_disposed) rmk_rdp_resize(_handle, w, h);
  }

  /// 本地剪贴板文本
  void setClipboardText(String text) {
    if (_disposed) return;
    using((arena) => rmk_rdp_set_clipboard_text(_handle, text.toNativeUtf8(allocator: arena)));
  }

  /// 本地剪贴板文件
  void setClipboardFiles(List<String> paths) {
    if (_disposed || paths.isEmpty) return;
    using((arena) => rmk_rdp_set_clipboard_files(_handle, paths.join('\n').toNativeUtf8(allocator: arena)));
  }

  /// 断开（会阻塞直到连接线程退出）
  void disconnect() {
    if (!_disposed) rmk_rdp_disconnect(_handle);
  }

  /// 释放
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _clients.remove(_id);
    rmk_rdp_free(_handle);
    if (_buffer != nullptr) malloc.free(_buffer);
    _buffer = nullptr;
  }
}
