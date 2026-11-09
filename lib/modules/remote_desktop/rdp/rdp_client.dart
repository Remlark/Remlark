import 'dart:ffi';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';

import '../frame_update.dart';
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
  static const clipReady = 11;
  static const h264Software = 12;
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
    this.hardwareDecode = true,
    this.audio = true,
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

  /// 是否允许 H.264 硬件解码（设置项，关闭或硬件不可用时软件解码）
  final bool hardwareDecode;

  /// 是否在本机播放远程声音（主机设置，关闭时服务器不发送声音）
  final bool audio;
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
  bool _disposed = false;

  /// takeFrame 的输出参数：[宽, 高, 块数, 是否整屏] 与区域列表（原生内存，复用）
  final Pointer<Int32> _info = malloc<Int32>(4);
  final Pointer<Int32> _rects = malloc<Int32>(rmkRdpMaxRects * 4);

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

  /// 服务端已确认本地剪贴板内容（[ok] 为 false 表示服务端拒绝）
  void Function(bool ok)? onClipboardReady;

  /// 硬件解码不支持服务端的 H.264 视频流（[width]×[height] 为表面尺寸），本次会话已改用软件解码
  void Function(int width, int height)? onH264Software;

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
      case RdpEvent.clipReady:
        client.onClipboardReady?.call(a == 1);
      case RdpEvent.h264Software:
        client.onH264Software?.call(a, b);
    }
  }

  /// 开始连接（异步，结果通过回调通知）
  void connect(RdpConnectOptions o) {
    using((arena) {
      Pointer<Utf8> s(String? v) => v == null || v.isEmpty ? nullptr : v.toNativeUtf8(allocator: arena);
      rmk_rdp_set_proxy(_handle, o.proxyType, s(o.proxyHost), o.proxyPort, s(o.proxyUser), s(o.proxyPassword));
      rmk_rdp_set_hwdec(_handle, o.hardwareDecode ? 1 : 0);
      rmk_rdp_set_audio(_handle, o.audio ? 1 : 0);
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

  /// 取出自上次调用以来的画面变化（只含变化区域），没有变化返回 null。
  /// 先查询所需大小，再由原生直接写入 Dart 的 Uint8List；两次调用之间若又有新变化则按新大小重试
  FrameUpdate? takeFrame() {
    if (_disposed) return null;
    final w = _info, h = _info + 1, n = _info + 2, full = _info + 3;
    var size = rmk_rdp_take_frame(_handle, nullptr, 0, w, h, _rects, n, full);
    while (size < 0) {
      final data = Uint8List(-size);
      size = rmk_rdp_take_frame(_handle, data.address, data.length, w, h, _rects, n, full);
      if (size > 0) {
        width = w.value;
        height = h.value;
        final patches = <FramePatch>[];
        var off = 0;
        for (var i = 0; i < n.value; i++) {
          final r = _rects + i * 4;
          final rw = r[2], rh = r[3];
          final len = rw * rh * 4;
          patches.add(FramePatch(r[0], r[1], rw, rh, Uint8List.sublistView(data, off, off + len)));
          off += len;
        }
        return FrameUpdate(width: width, height: height, full: full.value == 1, patches: patches);
      }
    }
    return null;
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
    malloc.free(_info);
    malloc.free(_rects);
  }
}
