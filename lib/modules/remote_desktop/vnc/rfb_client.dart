import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import '../../../utils/app_log.dart';
import '../../../utils/async_byte_reader.dart';
import '../../../utils/des.dart';
import 'ard_auth.dart';
import '../remote_display.dart';
import 'rfb_cursor.dart';

/// VNC 认证失败
class RfbAuthException implements Exception {
  RfbAuthException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// 需要凭据但未提供；[needUsername] 为 true 表示服务器使用 macOS 账户认证，还需要用户名
class RfbPasswordRequired implements Exception {
  RfbPasswordRequired({this.needUsername = false});

  final bool needUsername;
}

/// RFB（VNC）协议客户端：实现 3.3/3.7/3.8 握手、None / VNC / Apple Remote Desktop 认证、
/// Raw / CopyRect / ZRLE 编码、DesktopSize 与 Cursor 伪编码、键鼠事件与剪贴板。
/// 记录每次更新的变化区域，供界面只重绘变化部分。
/// 帧缓冲格式为 BGRA8888，可直接交给 Flutter 绘制。
class RfbClient {
  RfbClient();

  Socket? _socket;
  AsyncByteReader? _reader;

  /// 远程桌面宽高与名称
  int width = 0;
  int height = 0;
  String desktopName = '';

  /// 本次握手协商出的安全类型（1 无认证、2 VNC 密码、30 Apple Remote Desktop）
  int securityType = 0;

  /// 帧缓冲（BGRA）
  Uint8List framebuffer = Uint8List(0);

  /// 是否正在接收一次 FramebufferUpdate（矩形只更新了一部分）；
  /// 此时读取帧缓冲会得到新旧混合的画面（撕裂），调用方应等待 [onFrame]
  bool get updating => _updating;
  bool _updating = false;

  /// 帧缓冲更新回调（一次 FramebufferUpdate 完成后触发）
  void Function()? onFrame;

  /// 远程指针形状变化回调（null 表示隐藏指针）
  void Function(RemoteCursor? cursor)? onCursor;

  /// 自上次 [takeDirty] 以来变化的区域（x, y, w, h）；[_fullDirty] 为 true 表示整屏都需要刷新
  final List<(int, int, int, int)> _dirty = [];
  bool _fullDirty = true;

  /// 统计（定期写入日志后由调用方 [resetStats] 清零）：
  /// 更新次数、矩形数、数据字节数、各编码矩形数、
  /// 等待耗时（发出请求到收到更新头）、接收耗时（更新头到最后一个矩形处理完）、发送的鼠标 / 键盘事件数
  int statUpdates = 0;
  int statRects = 0;
  int statBytes = 0;
  final Map<int, int> statEncodings = {};
  int statWaitMs = 0, statWaitMax = 0;
  int statRecvMs = 0, statRecvMax = 0;
  int statPointers = 0, statKeys = 0, statRequests = 0;

  /// 输入→画面延迟：发出点击 / 按键 / 滚轮后到收到下一次更新头的时间（服务器响应速度，直接对应体感延迟）
  int statInputSamples = 0, statInputMs = 0, statInputMax = 0;
  int? _inputAt;

  /// 清零统计
  void resetStats() {
    statUpdates = statRects = statBytes = 0;
    statWaitMs = statWaitMax = statRecvMs = statRecvMax = 0;
    statPointers = statKeys = statRequests = statPresents = 0;
    statInputSamples = statInputMs = statInputMax = 0;
    statVerify = statVerifyDiff = statRefresh = 0;
    statEncodings.clear();
  }

  /// 呈现统计：通知界面的帧数、被合并进同一帧的更新数
  int statPresents = 0;

  /// 更新呈现（参考 noVNC：每次更新完整处理完即呈现，渲染按帧自然合并）：
  /// 一次更新处理完时，若网络缓冲中已有后续数据则先继续处理（不额外等待），缓冲读空后立即呈现；
  /// 连续积压超过 [_maxCoalesceMs] 也强制呈现，保证持续变化时画面不停顿
  static const _maxCoalesceMs = 50;
  int? _pendingSince;

  /// 一次更新处理完
  void _frameReady() {
    final now = _clock.elapsedMilliseconds;
    _pendingSince ??= now;
    if (_reader!.available == 0 || now - _pendingSince! >= _maxCoalesceMs) _present();
  }

  void _present() {
    _pendingSince = null;
    if (_closed) return;
    statPresents++;
    onFrame?.call();
  }

  /// 整屏校验：空闲时请求一次整屏（非增量），收到覆盖整屏的更新时与当前帧缓冲逐像素比对，
  /// 有差异说明此前的增量更新漏掉了变化（服务器未发送或解码错误），并记录差异范围；整屏同时修复画面
  bool _verifyPending = false;
  int _verifyWait = 0;
  int statVerify = 0, statVerifyDiff = 0;

  /// 空闲：不在接收更新、没有待呈现的更新、没有未取走的变化区域（此时帧缓冲已全部交给界面）
  bool get idle => !_updating && _pendingSince == null && _dirty.isEmpty && !_fullDirty && !_verifyPending;

  /// 请求整屏校验
  void requestVerify() {
    if (_closed || _verifyPending) return;
    _verifyPending = true;
    _verifyWait = 0;
    requestUpdate(incremental: false);
  }

  /// 比对整屏更新前后的帧缓冲，返回差异像素数与范围
  (int, (int, int, int, int)?) _diffFrame(Uint8List before) {
    final fb = framebuffer;
    if (before.length != fb.length) return (-1, null);
    final a = before.buffer.asUint32List(before.offsetInBytes, before.length ~/ 4);
    final b = fb.buffer.asUint32List(fb.offsetInBytes, fb.length ~/ 4);
    var n = 0;
    var l = width, t = height, r = 0, btm = 0;
    for (var i = 0; i < a.length; i++) {
      if (a[i] == b[i]) continue;
      n++;
      final x = i % width, y = i ~/ width;
      if (x < l) l = x;
      if (y < t) t = y;
      if (x >= r) r = x + 1;
      if (y >= btm) btm = y + 1;
    }
    return (n, n == 0 ? null : (l, t, r, btm));
  }

  /// 单次更新接收超过该时长写警告日志
  static const _slowRecvMs = 300;

  final _clock = Stopwatch()..start();
  int _lastRequestAt = 0;

  /// 远程尺寸变化回调
  void Function(int w, int h)? onResize;

  /// 远程剪贴板文本回调
  void Function(String text)? onClipboard;

  /// 连接关闭回调
  void Function(Object? error)? onClosed;

  /// 响铃回调
  void Function()? onBell;

  RawZLibFilter? _zlib;
  bool _closed = false;

  static const _encRaw = 0;
  static const _encCopyRect = 1;
  static const _encZrle = 16;
  static const _encDesktopSize = -223;
  static const _encCursor = -239;
  static const _encFence = -312;
  static const _encContinuousUpdates = -313;

  /// 服务器支持并已启用 ContinuousUpdates：服务器在画面变化时主动推送，客户端不再逐次请求
  bool get continuousUpdates => _continuous;
  bool _continuous = false;

  /// 连接并完成握手；凭据不足以完成服务器要求的认证时抛出 [RfbPasswordRequired]。
  /// [username] 仅用于 Apple Remote Desktop 认证（macOS 系统账户）
  Future<void> connect(String host, int port, {String? username, String? password}) async {
    AppLog.i('vnc', '连接 $host:$port');
    final socket = await Socket.connect(host, port, timeout: const Duration(seconds: 15));
    socket.setOption(SocketOption.tcpNoDelay, true);
    AppLog.i('vnc', 'TCP 已连接 ${socket.remoteAddress.address}:${socket.remotePort}');
    _socket = socket;
    final r = AsyncByteReader(socket);
    _reader = r;
    const t = Duration(seconds: 20);

    // 1. 协议版本
    final ver = ascii.decode(await r.read(12, timeout: t));
    final m = RegExp(r'RFB (\d{3})\.(\d{3})').firstMatch(ver);
    if (m == null) throw const FormatException('not a VNC server');
    final minor = int.parse(m.group(2)!);
    final useMinor = minor >= 8 ? 8 : (minor >= 7 ? 7 : 3);
    socket.add(ascii.encode('RFB 003.00$useMinor\n'));
    AppLog.i('vnc', '服务器协议 ${ver.trim()}，使用 3.$useMinor');

    // 2. 安全类型协商
    int secType;
    if (useMinor == 3) {
      secType = await r.u32();
      if (secType == 0) throw RfbAuthException(await _readReason());
    } else {
      final n = await r.u8();
      if (n == 0) throw RfbAuthException(await _readReason());
      final types = await r.read(n, timeout: t);
      AppLog.i('vnc', '服务器安全类型 $types');
      final hasUser = username?.isNotEmpty ?? false;
      final hasPass = password?.isNotEmpty ?? false;
      if (types.contains(ArdAuth.securityType) && hasUser) {
        // 填写了用户名时优先使用 macOS 账户认证
        secType = ArdAuth.securityType;
      } else if (types.contains(2) && hasPass) {
        secType = 2;
      } else if (types.contains(1)) {
        secType = 1;
      } else if (types.contains(2)) {
        secType = 2;
      } else if (types.contains(ArdAuth.securityType)) {
        secType = ArdAuth.securityType;
      } else {
        throw RfbAuthException('unsupported security types: $types');
      }
      securityType = secType;
      AppLog.i('vnc', '选择安全类型 $secType（用户名${hasUser ? '已填' : '未填'}，密码${hasPass ? '已填' : '未填'}）');
      if (secType == ArdAuth.securityType && (!hasUser || !hasPass)) {
        throw RfbPasswordRequired(needUsername: true);
      }
      socket.add([secType]);
    }

    // 3. 认证
    if (secType == 2) {
      if (password == null || password.isEmpty) {
        throw RfbPasswordRequired();
      }
      final challenge = await r.read(16, timeout: t);
      socket.add(Des.vncResponse(password, challenge));
    } else if (secType == ArdAuth.securityType) {
      // DH 参数：生成元(2) + 密钥长度(2) + 素数(keyLen) + 服务器公钥(keyLen)
      final generator = await r.u16();
      final keyLen = await r.u16();
      AppLog.i('vnc', 'ARD 认证：DH 生成元 $generator，密钥长度 $keyLen 字节');
      final prime = await r.read(keyLen, timeout: t);
      final serverPub = await r.read(keyLen, timeout: t);
      socket.add(
        ArdAuth.response(
          generator: generator,
          prime: prime,
          serverPublicKey: serverPub,
          username: username!,
          password: password!,
        ),
      );
    }
    if (secType == 2 || secType == ArdAuth.securityType || useMinor == 8) {
      final result = await r.u32();
      if (result != 0) {
        final reason = useMinor == 8 ? await _readReason() : 'authentication failed';
        AppLog.w('vnc', '认证失败：$reason');
        throw RfbAuthException(reason);
      }
      AppLog.i('vnc', '认证成功');
    }

    // 4. ClientInit（共享桌面）/ ServerInit
    socket.add([1]);
    width = await r.u16();
    height = await r.u16();
    final pf = await r.read(16); // 服务器像素格式，下面会强制设置为我们需要的格式
    final nameLen = await r.u32();
    desktopName = utf8.decode(await r.read(nameLen), allowMalformed: true);
    framebuffer = Uint8List(width * height * 4);
    AppLog.i(
      'vnc',
      'ServerInit：$width×$height「$desktopName」，服务器像素格式 bpp=${pf[0]} depth=${pf[1]} '
          'bigEndian=${pf[2]} trueColor=${pf[3]} shift=${pf[10]}/${pf[11]}/${pf[12]}',
    );

    _setPixelFormat();
    _setEncodings();
    requestUpdate(incremental: false);
    unawaited(_loop());
  }

  Future<String> _readReason() async {
    final len = await _reader!.u32();
    return utf8.decode(await _reader!.read(len), allowMalformed: true);
  }

  /// 设置像素格式：32bpp、深度 24、小端、真彩色，R/G/B 位移 16/8/0（内存顺序 BGRX）
  void _setPixelFormat() {
    final b = ByteData(20);
    b.setUint8(0, 0);
    b.setUint8(4, 32); // bits-per-pixel
    b.setUint8(5, 24); // depth
    b.setUint8(6, 0); // big-endian flag
    b.setUint8(7, 1); // true-colour
    b.setUint16(8, 255);
    b.setUint16(10, 255);
    b.setUint16(12, 255);
    b.setUint8(14, 16);
    b.setUint8(15, 8);
    b.setUint8(16, 0);
    _socket!.add(b.buffer.asUint8List());
  }

  /// 声明支持的编码（优先 ZRLE）；声明 Cursor 伪编码后指针由本地绘制
  void _setEncodings() {
    // Fence 与 ContinuousUpdates（与 noVNC / TigerVNC 一致）：服务器支持时改为推送模式，省去每次请求的往返
    const encs = [_encZrle, _encCopyRect, _encRaw, _encCursor, _encDesktopSize, _encFence, _encContinuousUpdates];
    final b = ByteData(4 + encs.length * 4);
    b.setUint8(0, 2);
    b.setUint16(2, encs.length);
    for (var i = 0; i < encs.length; i++) {
      b.setInt32(4 + i * 4, encs[i]);
    }
    _socket!.add(b.buffer.asUint8List());
    AppLog.i('vnc', '声明编码 $encs，像素格式 32bpp BGRX');
  }

  /// 请求帧缓冲更新
  void requestUpdate({bool incremental = true}) {
    if (_closed || _socket == null) return;
    final b = ByteData(10);
    b.setUint8(0, 3);
    b.setUint8(1, incremental ? 1 : 0);
    b.setUint16(6, width);
    b.setUint16(8, height);
    _socket!.add(b.buffer.asUint8List());
    _lastRequestAt = _clock.elapsedMilliseconds;
    statRequests++;
    if (!incremental) AppLog.i('vnc', '请求整屏更新 $width×$height');
  }

  /// 请求某个区域的完整画面（非增量）：服务器偶尔漏报变化（如菜单淡入），点击后对指针附近补一次
  void requestRegionRefresh(int x, int y, int w, int h) {
    if (_closed || _socket == null || width == 0) return;
    final x0 = x.clamp(0, width - 1), y0 = y.clamp(0, height - 1);
    final x1 = (x + w).clamp(x0 + 1, width), y1 = (y + h).clamp(y0 + 1, height);
    final b = ByteData(10);
    b.setUint8(0, 3);
    b.setUint8(1, 0);
    b.setUint16(2, x0);
    b.setUint16(4, y0);
    b.setUint16(6, x1 - x0);
    b.setUint16(8, y1 - y0);
    _socket!.add(b.buffer.asUint8List());
    statRefresh++;
  }

  /// 统计：点击后区域补刷新次数
  int statRefresh = 0;

  /// 启用 ContinuousUpdates（整屏区域）
  void _enableContinuous() {
    if (_closed) return;
    _continuous = true;
    final b = ByteData(10);
    b.setUint8(0, 150);
    b.setUint8(1, 1);
    b.setUint16(6, width);
    b.setUint16(8, height);
    _socket!.add(b.buffer.asUint8List());
  }

  /// 回应服务器 Fence
  void _sendFence(int flags, Uint8List payload) {
    if (_closed) return;
    final b = ByteData(9);
    b.setUint8(0, 248);
    b.setUint32(4, flags);
    b.setUint8(8, payload.length);
    _socket!.add(b.buffer.asUint8List());
    _socket!.add(payload);
  }

  /// 发送键盘事件（X11 keysym）
  void sendKey(int keysym, bool down) {
    if (_closed) return;
    if (down) _inputAt ??= _clock.elapsedMilliseconds;
    final b = ByteData(8);
    b.setUint8(0, 4);
    b.setUint8(1, down ? 1 : 0);
    b.setUint32(4, keysym);
    _socket?.add(b.buffer.asUint8List());
    statKeys++;
  }

  /// 发送鼠标事件；[buttons] 位掩码：1 左键、2 中键、4 右键、8 滚轮上、16 滚轮下。
  /// [input] 为 true 表示用户操作（点击 / 滚轮），用于统计输入→画面延迟
  void sendPointer(int x, int y, int buttons, {bool input = false}) {
    if (input) _inputAt ??= _clock.elapsedMilliseconds;
    if (_closed) return;
    final b = ByteData(6);
    b.setUint8(0, 5);
    b.setUint8(1, buttons);
    b.setUint16(2, x.clamp(0, width > 0 ? width - 1 : 0));
    b.setUint16(4, y.clamp(0, height > 0 ? height - 1 : 0));
    _socket?.add(b.buffer.asUint8List());
    statPointers++;
  }

  /// 发送剪贴板文本到远程（RFB 规定为 Latin-1，无法表示的字符替换为 ?）
  void sendClipboard(String text) {
    if (_closed) return;
    final bytes = Uint8List.fromList(text.codeUnits.map((c) => c < 256 ? c : 0x3f).toList());
    final b = ByteData(8);
    b.setUint8(0, 6);
    b.setUint32(4, bytes.length);
    _socket?.add(b.buffer.asUint8List());
    _socket?.add(bytes);
  }

  /// 主消息循环
  Future<void> _loop() async {
    final r = _reader!;
    Object? error;
    try {
      while (!_closed) {
        // 待呈现的更新后面跟的是其他消息（如剪贴板）且缓冲已读空时，不再等待下一次更新
        if (_pendingSince != null && r.available == 0) _present();
        final type = await r.u8();
        switch (type) {
          case 0:
            _updating = true;
            var resized = false;
            try {
              resized = await _readFramebufferUpdate();
            } finally {
              _updating = false;
            }
            // 与 noVNC / TigerVNC 一致：处理完一次更新再请求下一次（尺寸变化后请求整屏）；
            // 推送模式下无需请求，尺寸变化时按新尺寸重新启用
            if (!_continuous) {
              requestUpdate(incremental: !resized);
            } else if (resized) {
              _enableContinuous();
            }
            _frameReady();
          case 1:
            await r.read(1);
            await r.u16();
            final n = await r.u16();
            await r.read(n * 6);
          case 2:
            onBell?.call();
          case 3:
            await r.read(3);
            final len = await r.s32();
            if (len < 0) {
              // 扩展剪贴板格式，暂不支持，跳过
              await r.read(-len);
            } else {
              final data = await r.read(len);
              AppLog.d('vnc', '收到远程剪贴板 $len 字节');
              onClipboard?.call(_decodeClipboard(data));
            }
          case 150:
            // EndOfContinuousUpdates：服务器支持 ContinuousUpdates（首次收到即启用）
            if (!_continuous) {
              AppLog.i('vnc', '服务器支持 ContinuousUpdates，启用推送模式');
              _enableContinuous();
            } else {
              AppLog.i('vnc', '服务器结束 ContinuousUpdates，恢复请求模式');
              _continuous = false;
              requestUpdate();
            }
          case 248:
            // 服务器 Fence：带请求标志时按原负载回应（只保留 BlockBefore / BlockAfter 标志）
            await r.read(3);
            final flags = await r.u32();
            final len = await r.u8();
            final payload = await r.read(len);
            AppLog.d('vnc', '收到服务器 Fence flags=0x${flags.toRadixString(16)} 负载 $len 字节');
            if (flags & 0x80000000 != 0) _sendFence(flags & 0x3, payload);
          default:
            AppLog.e('vnc', '未知的服务器消息类型 $type');
            throw FormatException('unknown server message $type');
        }
      }
    } catch (e, st) {
      if (!_closed) {
        error = e;
        AppLog.e('vnc', '接收循环异常，连接断开', e, st);
      }
    }
    AppLog.i('vnc', '连接关闭${error == null ? '' : '：$error'}');
    _closed = true;
    _socket?.destroy();
    onClosed?.call(error);
  }

  /// 剪贴板：优先按 UTF-8 解码（很多服务器实际发送 UTF-8），失败按 Latin-1
  static String _decodeClipboard(Uint8List data) {
    try {
      return utf8.decode(data);
    } catch (_) {
      return latin1.decode(data);
    }
  }

  /// 读取并应用一次 FramebufferUpdate，返回是否包含尺寸变化
  Future<bool> _readFramebufferUpdate() async {
    final r = _reader!;
    await r.read(1);
    final n = await r.u16();
    final headerAt = _clock.elapsedMilliseconds;
    final wait = headerAt - _lastRequestAt;
    final inputAt = _inputAt;
    if (inputAt != null) {
      final lat = headerAt - inputAt;
      _inputAt = null;
      statInputSamples++;
      statInputMs += lat;
      if (lat > statInputMax) statInputMax = lat;
      if (lat > 500) AppLog.w('vnc', '输入后 ${lat}ms 才收到画面更新');
    }
    statUpdates++;
    statRects += n;
    statWaitMs += wait;
    if (wait > statWaitMax) statWaitMax = wait;
    final bytesBefore = statBytes;
    final encs = <int>[];
    // 整屏校验：先保存更新前的帧缓冲，若本次更新覆盖整屏则比对
    final before = _verifyPending ? Uint8List.fromList(framebuffer) : null;
    var coversFull = false;
    var resized = false;
    for (var i = 0; i < n; i++) {
      final x = await r.u16();
      final y = await r.u16();
      final w = await r.u16();
      final h = await r.u16();
      final enc = await r.s32();
      if (x == 0 && y == 0 && w == width && h == height && enc != _encCursor && enc != _encDesktopSize) {
        coversFull = true;
      }
      statEncodings[enc] = (statEncodings[enc] ?? 0) + 1;
      if (encs.length < 8) encs.add(enc);
      switch (enc) {
        case _encRaw:
          await _readRaw(x, y, w, h);
          _markDirty(x, y, w, h);
        case _encCopyRect:
          final sx = await r.u16();
          final sy = await r.u16();
          _copyRect(sx, sy, x, y, w, h);
          _markDirty(x, y, w, h);
        case _encZrle:
          await _readZrle(x, y, w, h);
          _markDirty(x, y, w, h);
        case _encCursor:
          // x, y 为热点；像素数据后跟位掩码
          final pixels = await r.read(w * h * 4);
          final mask = await r.read(((w + 7) ~/ 8) * h);
          AppLog.d('vnc', '指针形状 $w×$h 热点 ($x,$y)');
          onCursor?.call(RfbCursor.decode(w, h, x, y, pixels, mask));
        case _encDesktopSize:
          AppLog.i('vnc', '远程尺寸变化 $width×$height → $w×$h');
          _resize(w, h);
          resized = true;
        default:
          AppLog.e('vnc', '不支持的编码 $enc（矩形 $x,$y $w×$h）');
          throw FormatException('unsupported encoding $enc');
      }
    }
    if (before != null && !coversFull && ++_verifyWait >= 5) {
      // 服务器把整屏拆成多个矩形发送等情况：放弃本次校验，避免每次更新都复制帧缓冲
      _verifyPending = false;
      AppLog.d('vnc.verify', '整屏校验：5 次更新内未收到单个整屏矩形，放弃本次校验');
    }
    if (before != null && coversFull && !resized) {
      _verifyPending = false;
      statVerify++;
      final (n, box) = _diffFrame(before);
      if (n > 0) {
        statVerifyDiff++;
        AppLog.w('vnc.verify', '整屏校验：增量更新遗漏了 $n 个像素，范围 $box（服务器未发送该变化或解码错误），已用整屏修复');
      } else {
        AppLog.d('vnc.verify', '整屏校验：帧缓冲与服务器一致');
      }
    }
    final recv = _clock.elapsedMilliseconds - headerAt;
    statRecvMs += recv;
    if (recv > statRecvMax) statRecvMax = recv;
    if (recv > _slowRecvMs) {
      AppLog.w('vnc', '慢更新：接收 ${recv}ms，等待 ${wait}ms，$n 个矩形，${(statBytes - bytesBefore) ~/ 1024}KB，编码 $encs');
    }
    return resized;
  }

  /// 记录变化区域
  void _markDirty(int x, int y, int w, int h) {
    if (_fullDirty || w <= 0 || h <= 0) return;
    _dirty.add((x, y, w, h));
  }

  /// 取出并清空自上次调用以来的变化区域；返回 null 表示需要整屏刷新（首次或尺寸变化）
  List<(int, int, int, int)>? takeDirty() {
    if (_fullDirty) {
      _fullDirty = false;
      _dirty.clear();
      return null;
    }
    final r = List.of(_dirty);
    _dirty.clear();
    return r;
  }

  void _resize(int w, int h) {
    width = w;
    height = h;
    framebuffer = Uint8List(w * h * 4);
    _fullDirty = true;
    onResize?.call(w, h);
  }

  Future<void> _readRaw(int x, int y, int w, int h) async {
    statBytes += w * h * 4;
    final data = await _reader!.read(w * h * 4);
    for (var row = 0; row < h; row++) {
      final dst = ((y + row) * width + x) * 4;
      final src = row * w * 4;
      framebuffer.setRange(dst, dst + w * 4, data, src);
      for (var c = 0; c < w; c++) {
        framebuffer[dst + c * 4 + 3] = 255;
      }
    }
  }

  void _copyRect(int sx, int sy, int dx, int dy, int w, int h) {
    final tmp = Uint8List(w * h * 4);
    for (var row = 0; row < h; row++) {
      final s = ((sy + row) * width + sx) * 4;
      tmp.setRange(row * w * 4, (row + 1) * w * 4, framebuffer, s);
    }
    for (var row = 0; row < h; row++) {
      final d = ((dy + row) * width + dx) * 4;
      framebuffer.setRange(d, d + w * 4, tmp, row * w * 4);
    }
  }

  /// ZRLE：zlib 流在整个连接中连续，按 64x64 瓦片解析
  Future<void> _readZrle(int x, int y, int w, int h) async {
    final len = await _reader!.u32();
    statBytes += len;
    final compressed = await _reader!.read(len);
    final z = _zlib ??= RawZLibFilter.inflateFilter();
    z.process(compressed, 0, compressed.length);
    final out = BytesBuilder(copy: false);
    while (true) {
      final chunk = z.processed(flush: true);
      if (chunk == null || chunk.isEmpty) break;
      out.add(chunk);
    }
    final data = out.takeBytes();
    var pos = 0;

    // 读取一个 CPIXEL（3 字节：B G R）并写入帧缓冲
    for (var ty = y; ty < y + h; ty += 64) {
      final th = (y + h - ty) < 64 ? (y + h - ty) : 64;
      for (var tx = x; tx < x + w; tx += 64) {
        final tw = (x + w - tx) < 64 ? (x + w - tx) : 64;
        final sub = data[pos++];
        if (sub == 0) {
          for (var j = 0; j < th; j++) {
            for (var i = 0; i < tw; i++) {
              _put(tx + i, ty + j, data, pos);
              pos += 3;
            }
          }
        } else if (sub == 1) {
          final cp = pos;
          pos += 3;
          for (var j = 0; j < th; j++) {
            for (var i = 0; i < tw; i++) {
              _put(tx + i, ty + j, data, cp);
            }
          }
        } else if (sub >= 2 && sub <= 16) {
          final palette = pos;
          pos += sub * 3;
          final bits = sub == 2 ? 1 : (sub <= 4 ? 2 : 4);
          final mask = (1 << bits) - 1;
          for (var j = 0; j < th; j++) {
            var shift = 8 - bits;
            var byte = data[pos];
            for (var i = 0; i < tw; i++) {
              final idx = (byte >> shift) & mask;
              _put(tx + i, ty + j, data, palette + idx * 3);
              shift -= bits;
              if (shift < 0 && i < tw - 1) {
                shift = 8 - bits;
                byte = data[++pos];
              }
            }
            pos++;
          }
        } else if (sub == 128) {
          var i = 0;
          final total = tw * th;
          while (i < total) {
            final cp = pos;
            pos += 3;
            var run = 1;
            int b;
            do {
              b = data[pos++];
              run += b;
            } while (b == 255);
            for (var k = 0; k < run && i < total; k++, i++) {
              _put(tx + i % tw, ty + i ~/ tw, data, cp);
            }
          }
        } else if (sub >= 130) {
          final palette = pos;
          pos += (sub - 128) * 3;
          var i = 0;
          final total = tw * th;
          while (i < total) {
            var idx = data[pos++];
            var run = 1;
            if (idx & 128 != 0) {
              idx &= 127;
              int b;
              do {
                b = data[pos++];
                run += b;
              } while (b == 255);
            }
            for (var k = 0; k < run && i < total; k++, i++) {
              _put(tx + i % tw, ty + i ~/ tw, data, palette + idx * 3);
            }
          }
        } else {
          throw FormatException('bad ZRLE subencoding $sub');
        }
      }
    }
  }

  /// 写入一个像素（CPIXEL 为 B G R）
  void _put(int px, int py, Uint8List src, int off) {
    final d = (py * width + px) * 4;
    framebuffer[d] = src[off];
    framebuffer[d + 1] = src[off + 1];
    framebuffer[d + 2] = src[off + 2];
    framebuffer[d + 3] = 255;
  }

  /// 断开连接
  void close() {
    if (_closed) return;
    _closed = true;
    _socket?.destroy();
  }
}
