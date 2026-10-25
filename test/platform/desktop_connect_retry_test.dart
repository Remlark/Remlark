import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:remlark/modules/hosts/host_model.dart';
import 'package:remlark/modules/hosts/host_repository.dart';
import 'package:remlark/modules/remote_desktop/rdp/rdp_client.dart';
import 'package:remlark/modules/remote_desktop/rdp/rdp_connect_error.dart';
import 'package:remlark/modules/remote_desktop/rdp/rdp_session.dart';
import 'package:remlark/modules/remote_desktop/remote_desktop_interaction.dart';
import 'package:remlark/modules/remote_desktop/vnc/rfb_client.dart';
import 'package:remlark/modules/remote_desktop/vnc/rfb_isolate_client.dart';
import 'package:remlark/modules/ssh/ssh_interaction.dart';
import 'package:remlark/modules/workspace/workspace_tab.dart';
import 'package:remlark/utils/network/connect_error_policy_linux.dart';
import 'package:remlark/utils/network/connect_error_policy_macos.dart';
import 'package:remlark/utils/network/connect_error_policy_windows.dart';
import 'package:remlark/utils/network/connect_retry.dart';
import 'package:remlark/utils/platform_utils.dart';

/// 多平台测试 P-29：VNC TCP 恢复、RDP 原生错误分类与有限重试、取消及旧回调隔离。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  for (final name in ['macOS', 'Windows', 'Linux']) {
    test('$name：RDP 网络错误最多四次，认证/TLS/权限/取消不自动重试', () async {
      for (final code in [
        0x20004,
        0x20006,
        0x2000d,
        0x20005,
        0x20008,
        0x20009,
        0x2000b,
        0x20016,
        0,
      ]) {
        var calls = 0;
        final pauses = <Duration>[];
        final error = RdpConnectError(code, '原生错误');
        await expectLater(
          ConnectRetry.run<void>(
            (_) async {
              calls++;
              throw error;
            },
            timeout: const Duration(seconds: 60),
            retryIf: (e) => e is RdpConnectError && e.retryable,
            wait: (d) async => pauses.add(d),
          ),
          throwsA(same(error)),
        );
        expect(calls, error.retryable ? 4 : 1);
        expect(pauses.length, error.retryable ? 3 : 0);
      }
    });
  }

  test('退避时关闭后停止重试', () async {
    var calls = 0;
    var cancelled = false;
    await expectLater(
      ConnectRetry.run<void>(
        (_) async {
          calls++;
          throw const RdpConnectError(0x20006, '连接失败');
        },
        timeout: const Duration(seconds: 60),
        retryIf: (_) => true,
        isCancelled: () => cancelled,
        wait: (_) async {
          cancelled = true;
        },
      ),
      throwsA(isA<ConnectRetryCancelled>()),
    );
    expect(calls, 1);
  });

  test('VNC 使用真实连接入口处理当前平台不可达，协议错误不重试', () async {
    final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(server.close);
    final accepted = server.first;
    final socket = await Socket.connect('127.0.0.1', server.port);
    final remote = await accepted;
    addTearDown(socket.destroy);
    addTearDown(remote.destroy);
    // 成功建立 TCP 后故意返回错误协议，验证握手不会被自动重复。
    remote.add('BAD 003.008\n'.codeUnits);
    final code = Platform.isMacOS
        ? 65
        : Platform.isWindows
        ? 10065
        : 113;
    var calls = 0;
    final client = RfbClient();
    addTearDown(client.close);
    await IOOverrides.runZoned(
      () async {
        await expectLater(client.connect('test', 5900), throwsFormatException);
      },
      socketConnect:
          (host, port, {sourceAddress, sourcePort = 0, timeout}) async {
            if (++calls == 1) {
              throw SocketException('不可达', osError: OSError('测试', code));
            }
            return socket;
          },
    );
    expect(calls, 2);
  });

  test('VNC 立即关闭建连中的 isolate，连接 Future 必须结束', () async {
    final client = RfbIsolateClient();
    final connecting = client.connect('127.0.0.1', 5900);
    final assertion = expectLater(connecting, throwsStateError);
    client.close();
    await assertion.timeout(const Duration(seconds: 5));
  });

  test('VNC 握手等待时关闭，停止后台连接并完成连接 Future', () async {
    final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(server.close);
    final accepted = server.first;
    final client = RfbIsolateClient();
    addTearDown(client.close);
    final assertion = expectLater(
      client.connect('127.0.0.1', server.port),
      throwsStateError,
    );
    final socket = await accepted;
    addTearDown(socket.destroy);
    final disconnected = socket.drain<void>();
    client.close();
    await assertion.timeout(const Duration(seconds: 5));
    await disconnected.timeout(const Duration(seconds: 5));
  });

  for (final (name, policy, code) in [
    ('macOS', const MacosConnectErrorPolicy(), 65),
    ('Windows', const WindowsConnectErrorPolicy(), 10065),
    ('Linux', const LinuxConnectErrorPolicy(), 113),
  ]) {
    test('$name：VNC 共用 TCP 策略首次不可达后恢复', () async {
      var calls = 0;
      expect(
        await ConnectRetry.run(
          (_) async {
            if (++calls == 1) {
              throw SocketException('不可达', osError: OSError('测试', code));
            }
            return 'connected';
          },
          timeout: const Duration(seconds: 15),
          policy: policy,
          wait: (_) async {},
        ),
        'connected',
      );
      expect(calls, 2);
    });
  }

  late Directory dir;
  setUp(() {
    dir = Directory.systemTemp.createTempSync('desktop_retry_');
    PlatformUtils.overrideDataDir(dir);
  });
  tearDown(() => dir.deleteSync(recursive: true));

  /// 使用真实会话流程与可控原生客户端，不要求安装 FreeRDP。
  RdpSession session(List<_Client> clients, List<int?> outcomes) {
    final s = RdpSession(
      _host(),
      _Hosts(),
      _Ui(),
      createClient: () {
        final c = _Client(outcomes[clients.length]);
        clients.add(c);
        return c;
      },
    );
    s.viewResized(800, 600);
    addTearDown(s.close);
    return s;
  }

  test('RDP 首次网络失败自动恢复，销毁旧客户端且忽略旧断开回调', () async {
    final clients = <_Client>[];
    final s = session(clients, [0x20006, null]);
    await s.connect();
    expect(s.state, SessionState.connected);
    expect(clients.length, 2);
    expect(clients.first.disposed, isTrue);
    clients.first.onDisconnected?.call(0x2000d, '迟到的旧回调');
    expect(s.state, SessionState.connected);
  });

  test('RDP 持续失败四次后显示最后错误', () async {
    final clients = <_Client>[];
    final s = session(clients, List.filled(4, 0x20006));
    await s.connect();
    expect(clients.length, 4);
    expect(s.state, SessionState.failed);
    expect(s.error, 'network failure');
    expect(clients.every((c) => c.disposed), isTrue);
  });

  test('RDP 退避期间关闭不创建第二个客户端', () async {
    final clients = <_Client>[];
    final s = session(clients, [0x20006]);
    final connecting = s.connect();
    while (clients.isEmpty) {
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
    await s.close();
    await connecting;
    expect(clients.length, 1);
    expect(s.state, SessionState.disconnected);
  });

  test('RDP 原生连接尚未返回时关闭，会完成等待且忽略迟到成功', () async {
    final clients = <_Client>[];
    final s = session(clients, [-1]);
    final connecting = s.connect();
    while (clients.isEmpty || !clients.first.started) {
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
    await s.close();
    await connecting;
    clients.first.onConnected?.call(800, 600);
    expect(s.state, SessionState.disconnected);
    expect(clients.single.disposed, isTrue);
  });

  test('RDP 认证失败仍请求凭据，证书变化仍要求确认', () async {
    for (final code in [0x20009, 0x20008]) {
      final ui = _Ui();
      final clients = <_Client>[];
      final s = RdpSession(
        _host(),
        _Hosts(),
        ui,
        createClient: () {
          final c = _Client(code, certificateChanged: code == 0x20008);
          clients.add(c);
          return c;
        },
      );
      s.viewResized(800, 600);
      addTearDown(s.close);
      await s.connect();
      expect(clients.length, 1);
      expect(ui.passwordAsked, code == 0x20009 ? 1 : 0);
      expect(ui.certificateAsked, code == 0x20008 ? 1 : 0);
      expect(s.state, SessionState.failed);
      expect(s.error, 'cancelled');
    }
  });

  test('RDP 总预算耗尽会释放客户端，迟到成功不能恢复会话', () async {
    final client = _Client(-1);
    final s = RdpSession(
      _host(),
      _Hosts(),
      _Ui(),
      createClient: () => client,
      connectionTimeout: const Duration(milliseconds: 50),
    );
    s.viewResized(800, 600);
    addTearDown(s.close);
    await s.connect();
    expect(s.state, SessionState.failed);
    expect(s.error, 'desktop.connect_timeout');
    expect(client.disposed, isTrue);
    client.onConnected?.call(800, 600);
    expect(s.state, SessionState.failed);
  });

  test('RDP TLS 失败直接显示错误，不发起自动重试', () async {
    final clients = <_Client>[];
    final s = session(clients, [0x20008]);
    await s.connect();
    expect(clients.length, 1);
    expect(s.state, SessionState.failed);
  });
}

/// 创建保存凭据的主机，关闭剪贴板以隔离系统插件。
HostEntry _host() => HostEntry(
  uuid: 'rdp',
  protocol: HostProtocol.rdp,
  name: 'test',
  address: 'localhost',
  port: 3389,
  username: 'u',
  password: 'pw',
  savePassword: true,
  extra: {'clipboard': false},
  updatedAt: 0,
  createdAt: 0,
);

/// 只替换存储依赖，不参与重试决策。
class _Hosts implements HostRepository {
  /// 返回测试主机的代理快照。
  @override
  Future<HostEntry> resolveProxy(HostEntry host) async => host;

  /// 测试无需写入最后连接时间。
  @override
  Future<void> touchConnected(String uuid) async {}

  /// 未预期的存储调用应立即失败。
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// 已保存密码的用例无需弹窗。
class _Ui implements RemoteDesktopInteraction {
  int passwordAsked = 0;
  int certificateAsked = 0;

  /// 记录凭据请求并模拟用户取消。
  @override
  Future<PasswordInput?> askDesktopPassword(
    HostEntry host, {
    String? error,
    bool askUsername = false,
  }) async {
    passwordAsked++;
    return null;
  }

  /// 记录证书确认并模拟用户拒绝。
  @override
  Future<bool> confirmCertificateChanged(
    HostEntry host,
    String oldFingerprint,
    String newFingerprint,
  ) async {
    certificateAsked++;
    return false;
  }
}

/// 模拟原生回调，保留销毁后回调以检查跨尝试隔离。
class _Client implements RdpClient {
  _Client(this.code, {this.certificateChanged = false});
  final bool certificateChanged;
  final int? code;
  bool disposed = false;
  bool started = false;
  @override
  void Function(int, int)? onConnected;
  @override
  void Function(int, String?)? onDisconnected;
  @override
  void Function(String?)? onAuthFailed;
  @override
  void Function(bool, String)? onCertificate;

  /// 按用例发出连接、认证或证书回调。
  @override
  void connect(RdpConnectOptions options) {
    started = true;
    if (code == -1) return;
    if (certificateChanged) onCertificate?.call(true, 'new-fingerprint');
    if (code == 0x20009) onAuthFailed?.call('wrong password');
    if (code == null) {
      onConnected?.call(800, 600);
    } else {
      onDisconnected?.call(code!, 'network failure');
    }
  }

  /// 不触发额外回调，迟到回调由用例显式发出。
  @override
  void disconnect() {}

  /// 标记销毁，检查每次失败都释放了客户端。
  @override
  void dispose() {
    disposed = true;
  }

  /// 忽略本用例未涉及的显示和剪贴板回调设置。
  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}
