import 'dart:async';
import 'dart:isolate';
import 'dart:typed_data';

import '../../../utils/app_log.dart';
import '../remote_display.dart';
import 'rfb_client.dart';
import 'settle_refresher.dart';

/// 在后台 isolate 中运行 RFB 客户端的代理（多线程渲染流水线的 UI 侧）。
///
/// 线程分工：
/// - 后台 isolate：网络收发、协议解析、ZRLE 解码、维护帧缓冲、合并连续更新、提取变化区域像素
/// - UI isolate：只接收打包好的变化区域（TransferableTypedData 零拷贝）交给引擎解码，处理输入
/// - 光栅线程：GPU 合成（覆盖到上一帧）与渲染
///
/// 背压：同一时刻最多一帧在途。UI 取走一帧（[takeFrame]）即回执，后台才发送下一帧；
/// UI 处理不过来时，后台把新变化继续累积在自己的帧缓冲中，不会积压。
class RfbIsolateClient {
  Isolate? _isolate;
  SendPort? _toWorker;
  ReceivePort? _fromWorker;
  Completer<void>? _connected;
  Completer<void>? _ready;
  final List<FrameUpdate> _frames = [];
  bool _closed = false;

  int width = 0;
  int height = 0;
  String desktopName = '';

  /// 协商出的安全类型（认证失败时也会设置，用于判断是否需要用户名）
  int securityType = 0;

  /// 有新帧可取（[takeFrame]）
  void Function()? onFrame;
  void Function(int w, int h)? onResize;
  void Function(RemoteCursor? cursor)? onCursor;
  void Function(String text)? onClipboard;
  void Function(Object? error)? onClosed;
  void Function()? onBell;

  /// 连接并完成握手（在后台 isolate 中进行）；异常与 [RfbClient.connect] 一致
  Future<void> connect(String host, int port, {String? username, String? password}) async {
    if (_closed) throw StateError('VNC connection cancelled');
    final rp = ReceivePort();
    _fromWorker = rp;
    final ready = Completer<void>();
    _ready = ready;
    _connected = Completer<void>();
    // spawn 尚未返回也可能关闭标签；提前接住取消错误，后续 await 仍会抛出。
    ready.future.ignore();
    _connected!.future.ignore();
    rp.listen((m) => _onMessage(m as List<Object?>, ready));
    final isolate = await Isolate.spawn(rfbWorkerMain, rp.sendPort, debugName: 'rfb-$host');
    if (_closed) {
      isolate.kill(priority: Isolate.immediate);
      throw StateError('VNC connection cancelled');
    }
    _isolate = isolate;
    await ready.future;
    _toWorker!.send(['connect', host, port, username, password]);
    await _connected!.future;
  }

  void _onMessage(List<Object?> m, Completer<void> ready) {
    switch (m[0]) {
      case 'port':
        _toWorker = m[1] as SendPort;
        ready.complete();
      case 'log':
        AppLog.raw(m[1] as String);
      case 'connected':
        width = m[1] as int;
        height = m[2] as int;
        desktopName = m[3] as String;
        securityType = m[4] as int;
        _connected?.complete();
      case 'error':
        securityType = m[2] as int;
        final kind = m[1] as String;
        final Object err = switch (kind) {
          'password' => RfbPasswordRequired(needUsername: m[3] as bool),
          'auth' => RfbAuthException(m[3] as String),
          _ => StateError(m[3] as String),
        };
        _connected?.completeError(err);
        _shutdown();
      case 'frame':
        final w = m[1] as int, h = m[2] as int;
        final full = m[3] as bool;
        final rects = m[4] as Int32List;
        final data = (m[5] as TransferableTypedData).materialize().asUint8List();
        final patches = <FramePatch>[];
        var off = 0;
        for (var i = 0; i < rects.length; i += 4) {
          final len = rects[i + 2] * rects[i + 3] * 4;
          patches.add(
            FramePatch(rects[i], rects[i + 1], rects[i + 2], rects[i + 3], Uint8List.sublistView(data, off, off + len)),
          );
          off += len;
        }
        width = w;
        height = h;
        _frames.add(FrameUpdate(width: w, height: h, full: full, patches: patches));
        onFrame?.call();
      case 'resize':
        width = m[1] as int;
        height = m[2] as int;
        onResize?.call(width, height);
      case 'cursor':
        final data = m[5] as TransferableTypedData?;
        onCursor?.call(
          data == null
              ? null
              : RemoteCursor(
                  width: m[1] as int,
                  height: m[2] as int,
                  hotX: m[3] as int,
                  hotY: m[4] as int,
                  bgra: data.materialize().asUint8List(),
                ),
        );
      case 'clip':
        onClipboard?.call(m[1] as String);
      case 'bell':
        onBell?.call();
      case 'closed':
        final wasClosed = _closed;
        _shutdown();
        if (!wasClosed) onClosed?.call(m[1]);
    }
  }

  /// 取出待显示的更新（多帧合并），并回执后台可以发送下一帧
  FrameUpdate? takeFrame() {
    if (_frames.isEmpty) return null;
    final u = FrameUpdate.combine(_frames);
    _frames.clear();
    _toWorker?.send(const ['ack']);
    return u;
  }

  void sendKey(int keysym, bool down) => _toWorker?.send(['key', keysym, down]);

  /// [input] 为 true 表示用户操作（点击 / 滚轮），用于触发点击后的区域补刷新
  void sendPointer(int x, int y, int buttons, {bool input = false}) =>
      _toWorker?.send(['pointer', x, y, buttons, input]);

  void sendClipboard(String text) => _toWorker?.send(['clip', text]);

  /// 断开连接并结束后台 isolate
  void close() {
    if (_closed) return;
    _shutdown();
  }

  /// 完成取消等待，通知后台释放网络资源，再兜底结束 isolate。
  void _shutdown() {
    final connecting = _connected?.isCompleted == false;
    final cancelled = StateError('VNC connection cancelled');
    if (_ready?.isCompleted == false) _ready!.completeError(cancelled);
    if (connecting) _connected!.completeError(cancelled);
    if (!_closed) _toWorker?.send(const ['close']);
    _closed = true;
    _fromWorker?.close();
    // 后台收到 close 后自行退出；兜底在稍后强制结束
    final iso = _isolate;
    _isolate = null;
    // 先让后台关闭 socket；直接 kill isolate 不保证立即释放网络句柄。
    if (iso != null) Timer(const Duration(seconds: 2), iso.kill);
  }
}

/// 后台 isolate 入口
@pragma('vm:entry-point')
Future<void> rfbWorkerMain(SendPort toUi) async {
  final fromUi = ReceivePort();
  // 本 isolate 的日志转发到主 isolate 写入文件
  AppLog.forward = (line) => toUi.send(['log', line]);
  toUi.send(['port', fromUi.sendPort]);
  final worker = _RfbWorker(toUi);
  await for (final m in fromUi) {
    final msg = m as List<Object?>;
    if (msg[0] == 'close') {
      worker.close();
      break;
    }
    // 建连不能阻塞消息循环，否则握手等待/退避期间无法处理关闭请求。
    if (msg[0] == 'connect') {
      unawaited(worker.handle(msg));
    } else {
      await worker.handle(msg);
    }
  }
  fromUi.close();
}

/// 后台 isolate 中的工作者：持有 RfbClient，负责打包变化区域与背压
class _RfbWorker {
  _RfbWorker(this._toUi);

  final SendPort _toUi;
  RfbClient? _c;

  /// 已发送、UI 尚未取走的帧
  bool _inFlight = false;

  /// 在途期间又有新变化，等待回执后发送
  bool _waiting = false;

  /// 整屏校验：最近一次用户输入与校验的时间；输入停止 [_verifyIdleMs] 后校验，间隔至少 [_verifyGapMs]。
  /// 只把用户输入当作活动：画面更新（包括校验自身的整屏结果）不算，否则会无限循环请求整屏
  static const _verifyIdleMs = 400;
  static const _verifyGapMs = 1500;
  final _clock = Stopwatch()..start();
  int _lastActivity = 0;
  int _lastVerify = -_verifyGapMs;
  bool _activitySinceVerify = false;
  Timer? _verifyTimer;

  Future<void> handle(List<Object?> m) async {
    final c = _c;
    if (m[0] == 'key' || m[0] == 'pointer') _activity();
    // 按键与鼠标点击 / 滚轮之后缩短补刷新等待（纯移动不算）
    if (m[0] == 'key' || (m[0] == 'pointer' && m[4] == true)) _settle?.noteInput();
    switch (m[0]) {
      case 'connect':
        await _connect(m[1] as String, m[2] as int, m[3] as String?, m[4] as String?);
      case 'key':
        c?.sendKey(m[1] as int, m[2] as bool);
      case 'pointer':
        c?.sendPointer(m[1] as int, m[2] as int, m[3] as int);
        // 只有鼠标按键的按下 / 抬起触发补刷新；滚轮（第 4、5 键）连续滚动时不触发，避免反复请求大区域
        final buttons = m[3] as int;
        if (m[4] == true && c != null && buttons & 0x18 == 0) {
          _scheduleRefresh(c, m[1] as int, m[2] as int, pressed: buttons & 0x7 != 0);
        }
      case 'clip':
        c?.sendClipboard(m[1] as String);
      case 'ack':
        _inFlight = false;
        if (_waiting && c != null && !c.updating) _sendFrame();
    }
  }

  Future<void> _connect(String host, int port, String? user, String? pass) async {
    final c = RfbClient();
    _c = c;
    c.onFrame = () {
      if (_inFlight || c.updating) {
        _waiting = true;
        return;
      }
      _sendFrame();
    };
    c.onResize = (w, h) => _toUi.send(['resize', w, h]);
    c.onCursor = (cur) => _toUi.send([
      'cursor',
      cur?.width,
      cur?.height,
      cur?.hotX,
      cur?.hotY,
      cur == null ? null : TransferableTypedData.fromList([cur.bgra]),
    ]);
    c.onClipboard = (t) => _toUi.send(['clip', t]);
    c.onBell = () => _toUi.send(const ['bell']);
    c.onClosed = (e) {
      _settle?.dispose();
      _verifyTimer?.cancel();
      _toUi.send(['closed', e?.toString()]);
    };
    try {
      await c.connect(host, port, username: user, password: pass);
    } on RfbPasswordRequired catch (e) {
      _toUi.send(['error', 'password', c.securityType, e.needUsername]);
      c.close();
      return;
    } on RfbAuthException catch (e) {
      _toUi.send(['error', 'auth', c.securityType, e.message]);
      c.close();
      return;
    } catch (e) {
      _toUi.send(['error', 'other', c.securityType, '$e']);
      c.close();
      return;
    }
    _toUi.send(['connected', c.width, c.height, c.desktopName, c.securityType]);
    _settle = SettleRefresher(
      refresh: (rects) {
        for (final (x, y, w, h) in rects) {
          c.requestRegionRefresh(x, y, w, h);
        }
      },
    );
    _verifyTimer = Timer.periodic(const Duration(milliseconds: 200), (_) => _maybeVerify(c));
  }

  /// 点击后补刷新：macOS 服务器偶尔漏报变化（菜单淡入显示一半），点击后对指针附近请求完整画面。
  /// 补两次：[_refreshEarly] 尽快消除残缺，[_refreshLate] 覆盖菜单淡入动画（约 150~200ms）结束后的最终画面
  static const _refreshEarly = Duration(milliseconds: 120);
  static const _refreshLate = Duration(milliseconds: 400);
  static const _refreshSize = 1000;
  final List<Timer> _refreshTimers = [];

  /// 上一次按下鼠标的位置：旧菜单在这里，点击别处关闭旧菜单时服务器同样可能漏报“菜单消失”
  (int, int)? _lastPress;

  /// 画面静止后的区域补刷新（见 SettleRefresher），连接后创建
  SettleRefresher? _settle;

  void _scheduleRefresh(RfbClient c, int x, int y, {required bool pressed}) {
    for (final t in _refreshTimers) {
      t.cancel();
    }
    _refreshTimers.clear();
    final spots = <(int, int)>[(x, y)];
    final prev = _lastPress;
    if (prev != null && ((prev.$1 - x).abs() > _refreshSize ~/ 2 || (prev.$2 - y).abs() > _refreshSize ~/ 2)) {
      spots.add(prev);
    }
    if (pressed) _lastPress = (x, y);
    for (final d in [_refreshEarly, _refreshLate]) {
      _refreshTimers.add(
        Timer(d, () {
          // 区域以指针为中心偏右下（菜单通常在指针右下方展开）
          for (final (px, py) in spots) {
            c.requestRegionRefresh(px - _refreshSize ~/ 4, py - _refreshSize ~/ 4, _refreshSize, _refreshSize);
          }
        }),
      );
    }
  }

  void _activity() {
    _lastActivity = _clock.elapsedMilliseconds;
    _activitySinceVerify = true;
  }

  /// 输入停止后做一次整屏校验（后台比对增量结果，有遗漏写日志）；整屏到达后照常发送给界面，同时修复画面
  void _maybeVerify(RfbClient c) {
    final now = _clock.elapsedMilliseconds;
    if (!_activitySinceVerify || now - _lastActivity < _verifyIdleMs || now - _lastVerify < _verifyGapMs) return;
    if (_inFlight || _waiting || !c.idle) return;
    _activitySinceVerify = false;
    _lastVerify = now;
    c.requestVerify();
  }

  /// 取出累积的变化区域，提取像素打包发送（一次传输，零拷贝转移给 UI）
  void _sendFrame() {
    final c = _c!;
    final w = c.width, h = c.height;
    var rects = c.takeDirty();
    if (rects != null) {
      if (rects.isEmpty) {
        _waiting = false;
        return;
      }
      _settle?.noteChanges(rects, w, h);
      rects = DirtyMerge.merge(rects, w, h);
    }
    final full = rects == null;
    final list = rects ?? [(0, 0, w, h)];
    var total = 0;
    for (final r in list) {
      total += r.$3 * r.$4 * 4;
    }
    final data = Uint8List(total);
    final meta = Int32List(list.length * 4);
    var off = 0;
    for (var i = 0; i < list.length; i++) {
      final (x, y, rw, rh) = list[i];
      meta.setAll(i * 4, [x, y, rw, rh]);
      if (full) {
        data.setRange(0, total, c.framebuffer);
      } else {
        for (var row = 0; row < rh; row++) {
          final src = ((y + row) * w + x) * 4;
          data.setRange(off + row * rw * 4, off + (row + 1) * rw * 4, c.framebuffer, src);
        }
      }
      off += rw * rh * 4;
    }
    _inFlight = true;
    _waiting = false;
    _toUi.send([
      'frame',
      w,
      h,
      full,
      meta,
      TransferableTypedData.fromList([data]),
    ]);
  }

  void close() {
    _settle?.dispose();
    for (final t in _refreshTimers) {
      t.cancel();
    }
    _verifyTimer?.cancel();
    _c?.close();
  }
}
