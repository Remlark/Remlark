import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dartssh2/dartssh2.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:remlark/data/database.dart';
import 'package:remlark/modules/hosts/host_model.dart';
import 'package:remlark/modules/hosts/host_repository.dart';
import 'package:remlark/modules/remote_desktop/remote_desktop_interaction.dart';
import 'package:remlark/modules/remote_desktop/vnc/vnc_session.dart';
import 'package:remlark/modules/hosts/vnc_ssh_config.dart';
import 'package:remlark/modules/keys/key_model.dart';
import 'package:remlark/modules/keys/key_repository.dart';
import 'package:remlark/modules/keys/key_utils.dart';
import 'package:remlark/modules/remote_desktop/vnc/finder_locator.dart';
import 'package:remlark/modules/remote_desktop/vnc/ssh_clipboard.dart';
import 'package:remlark/modules/sftp/sftp_service.dart';
import 'package:remlark/modules/sftp/transfer_manager.dart';
import 'package:remlark/modules/ssh/ssh_connector.dart';
import 'package:remlark/modules/ssh/ssh_interaction.dart';
import 'package:remlark/modules/terminal/terminal_session.dart';
import 'package:remlark/modules/workspace/workspace_tab.dart';
import 'package:remlark/utils/async_byte_reader.dart';
import 'package:remlark/utils/crypto_utils.dart';
import 'package:remlark/utils/secret_store.dart';

import 'helpers/platform_tools.dart';

/// 测试用交互：不应弹出任何对话框
class _NoUi extends SshInteraction {
  final progress = <String>[];

  @override
  Future<PasswordInput?> askPassword(HostEntry host, {String? error}) async => null;

  @override
  Future<String?> askPassphrase(HostEntry host, {String? error}) async => null;

  @override
  Future<bool> confirmHostKeyChanged(HostEntry host, String keyType, String o, String n) async => false;

  @override
  Future<List<String>?> keyboardInteractive(HostEntry host, SSHUserInfoRequest request) async => null;

  @override
  void onProgress(String message) => progress.add(message);
}

/// 远程桌面交互：测试中不应弹出
class _NoDesktopUi implements RemoteDesktopInteraction {
  @override
  Future<PasswordInput?> askDesktopPassword(HostEntry host, {String? error, bool askUsername = false}) async => null;

  @override
  Future<bool> confirmCertificateChanged(HostEntry host, String oldFingerprint, String newFingerprint) async => false;
}

/// 极简 HTTP CONNECT 代理
Future<ServerSocket> _httpProxy(List<String> log) async {
  final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
  server.listen((client) async {
    final buf = <int>[];
    late StreamSubscription<List<int>> sub;
    sub = client.listen((data) async {
      buf.addAll(data);
      final s = latin1.decode(buf);
      final end = s.indexOf('\r\n\r\n');
      if (end < 0) return;
      sub.pause();
      final target = s.split(' ')[1];
      log.add(target);
      final parts = target.split(':');
      final up = await Socket.connect(parts[0], int.parse(parts[1]));
      client.add(latin1.encode('HTTP/1.1 200 Connection established\r\n\r\n'));
      final rest = buf.sublist(end + 4);
      if (rest.isNotEmpty) up.add(rest);
      sub.onData(up.add);
      sub.resume();
      up.listen(client.add, onDone: client.destroy);
    });
  });
  return server;
}

/// 极简 SOCKS5 代理（用户名密码认证）
Future<ServerSocket> _socks5(List<String> log) async {
  final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
  server.listen((client) async {
    final r = AsyncByteReader(client);
    await r.read(2 + 2); // ver, nmethods=2, methods
    client.add([5, 2]);
    await r.u8();
    final ul = await r.u8();
    final u = String.fromCharCodes(await r.read(ul));
    final pl = await r.u8();
    final p = String.fromCharCodes(await r.read(pl));
    client.add([1, u == 'u' && p == 'p' ? 0 : 1]);
    await r.read(4);
    final hl = await r.u8();
    final h = String.fromCharCodes(await r.read(hl));
    final port = await r.u16();
    log.add('$h:$port');
    final up = await Socket.connect(h, port);
    client.add([5, 0, 0, 1, 0, 0, 0, 0, 0, 0]);
    final (rest, sub) = r.detach();
    if (rest.isNotEmpty) up.add(rest);
    sub.onData(up.add);
    up.listen(client.add, onDone: client.destroy);
  });
  return server;
}

void main() {
  late Directory dir;
  late Process sshd;
  late int port;
  late HostRepository hosts;
  late KeyRepository keys;
  late SshConnector connector;
  // Windows 下环境变量为 USERNAME；取不到用户名时不运行（sshd 按系统用户认证）
  final user = currentUserName() ?? '';
  var available = true;

  setUpAll(() async {
    SecretStore.initForTest(CryptoUtils.randomBytes(32));
    // 本地 sshd 仅在 macOS / Linux 上以普通用户临时启动；Windows 的 OpenSSH Server 需管理员权限作为服务运行，
    // 不在这里启动，Windows 上的 SSH 按 docs/multi-platform-testing.md 的手工清单验证
    if (Platform.isWindows || user.isEmpty || !File('/usr/sbin/sshd').existsSync()) {
      available = false;
      return;
    }
    dir = Directory.systemTemp.createTempSync('rmk_ssh');
    await Process.run('ssh-keygen', ['-q', '-t', 'ed25519', '-N', '', '-f', '${dir.path}/host_key']);
    final g = await KeyUtils.generateEd25519('remlark-test');
    File('${dir.path}/authorized_keys').writeAsStringSync('${g.publicLine}\n');
    await Process.run('chmod', ['600', '${dir.path}/authorized_keys']);
    port = 20000 + DateTime.now().millisecond;
    final sftpServer = [
      '/usr/libexec/sftp-server',
      '/usr/lib/openssh/sftp-server',
      '/usr/lib/ssh/sftp-server',
    ].firstWhere((p) => File(p).existsSync(), orElse: () => 'internal-sftp');
    File('${dir.path}/sshd_config').writeAsStringSync('''
Port $port
ListenAddress 127.0.0.1
HostKey ${dir.path}/host_key
PidFile ${dir.path}/sshd.pid
AuthorizedKeysFile ${dir.path}/authorized_keys
PasswordAuthentication no
KbdInteractiveAuthentication no
PubkeyAuthentication yes
StrictModes no
AllowTcpForwarding yes
UsePAM no
Subsystem sftp $sftpServer
''');
    sshd = await Process.start('/usr/sbin/sshd', ['-D', '-e', '-f', '${dir.path}/sshd_config']);
    sshd.stderr.transform(utf8.decoder).listen((_) {});
    for (var i = 0; i < 50; i++) {
      try {
        (await Socket.connect('127.0.0.1', port)).destroy();
        break;
      } catch (_) {
        await Future.delayed(const Duration(milliseconds: 100));
      }
    }
    final db = AppDatabase(NativeDatabase.memory());
    hosts = HostRepository(db);
    keys = KeyRepository(db);
    connector = SshConnector(hosts, keys);
    await keys.save(
      KeyEntry(
        uuid: 'k1',
        name: 'test',
        keyType: g.keyType,
        privateKey: g.privatePem,
        publicKey: g.publicLine,
        createdAt: 0,
      ),
    );
  });

  tearDownAll(() {
    if (!available) return;
    sshd.kill();
    dir.deleteSync(recursive: true);
  });

  HostEntry host(String uuid, {List<String> jumps = const [], ProxyConfig proxy = const ProxyConfig()}) => HostEntry(
    uuid: uuid,
    protocol: HostProtocol.ssh,
    name: uuid,
    address: '127.0.0.1',
    port: port,
    username: user,
    authType: AuthType.key,
    keyUuid: 'k1',
    jumpChain: jumps,
    proxy: proxy,
    updatedAt: 0,
    createdAt: 0,
  );

  test('密钥登录、指纹记录、系统探测、执行命令', () async {
    if (!available) return markTestSkipped('sshd not available (macOS / Linux only)');
    await hosts.save(host('direct'));
    final conn = await connector.connect((await hosts.getByUuid('direct'))!, _NoUi());
    expect(utf8.decode(await conn.client.run('echo hi')).trim(), 'hi');
    final os = await connector.detectOs(conn);
    expect(os, isNotNull);
    final saved = (await hosts.getByUuid('direct'))!;
    expect(saved.hostKeyFingerprint, startsWith('SHA256:'));
    expect(saved.osId, os!.id);
    conn.close();
  });

  test('跳板链（两级）+ HTTP 代理', () async {
    if (!available) return markTestSkipped('sshd not available (macOS / Linux only)');
    final log = <String>[];
    final proxy = await _httpProxy(log);
    await hosts.save(
      host(
        'j1',
        proxy: ProxyConfig(type: ProxyType.http, host: '127.0.0.1', port: proxy.port),
      ),
    );
    await hosts.save(host('j2'));
    await hosts.save(host('target', jumps: ['j1', 'j2']));
    final ui = _NoUi();
    final conn = await connector.connect((await hosts.getByUuid('target'))!, ui);
    expect(ui.progress, ['j1', 'j2', 'target']);
    expect(conn.jumps.length, 2);
    expect(log, ['127.0.0.1:$port']);
    expect(utf8.decode(await conn.client.run('echo via-jump')).trim(), 'via-jump');
    conn.close();
    await proxy.close();
  });

  test('SOCKS5 代理（用户名密码）', () async {
    if (!available) return markTestSkipped('sshd not available (macOS / Linux only)');
    final log = <String>[];
    final proxy = await _socks5(log);
    await hosts.save(
      host(
        'socks',
        proxy: ProxyConfig(type: ProxyType.socks5, host: '127.0.0.1', port: proxy.port, username: 'u', password: 'p'),
      ),
    );
    final conn = await connector.connect((await hosts.getByUuid('socks'))!, _NoUi());
    expect(utf8.decode(await conn.client.run('echo socks')).trim(), 'socks');
    expect(log, ['127.0.0.1:$port']);
    conn.close();
    await proxy.close();
  });

  test('终端会话：打开 shell、输入命令、读取输出、断开', () async {
    if (!available) return markTestSkipped('sshd not available (macOS / Linux only)');
    final s = TerminalSession((await hosts.getByUuid('direct'))!, connector, _NoUi());
    await s.connect();
    expect(s.state, SessionState.connected);
    s.sendRaw('echo REMLARK_\$((40+2))\r');
    var found = false;
    for (var i = 0; i < 50 && !found; i++) {
      await Future.delayed(const Duration(milliseconds: 100));
      found = s.recentText(lines: 200).contains('REMLARK_42');
    }
    expect(found, isTrue);
    expect(s.sftp, isNotNull);
    await s.close();
  });

  test('VNC 主机内置 SSH：用同一主机的地址与用户名经密钥登录 SSH（无需单独的 SSH 主机）', () async {
    if (!available) return markTestSkipped('sshd not available (macOS / Linux only)');
    // 模拟 VNC 服务器（无认证）
    final rfb = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    rfb.listen((s) async {
      final r = AsyncByteReader(s);
      s.add('RFB 003.008\n'.codeUnits);
      await r.read(12);
      s.add([1, 1]);
      await r.u8();
      s.add([0, 0, 0, 0]);
      await r.u8();
      final init = ByteData(24)
        ..setUint16(0, 2)
        ..setUint16(2, 1)
        ..setUint32(20, 1);
      s.add([...init.buffer.asUint8List(), ...'t'.codeUnits]);
    });
    final extra = <String, dynamic>{};
    VncSshConfig(enabled: true, port: port, authType: AuthType.key, keyUuid: 'k1').writeTo(extra);
    final vncHost = HostEntry(
      uuid: 'vnc1',
      protocol: HostProtocol.vnc,
      name: 'vnc1',
      address: '127.0.0.1',
      port: rfb.port,
      username: user,
      extra: extra,
      updatedAt: 0,
      createdAt: 0,
    );
    await hosts.save(vncHost);
    final ui = _NoUi();
    final session = VncSession(vncHost, hosts, connector, ui, _NoDesktopUi());
    expect(session.hasSsh, isTrue);
    final conn = await session.prepareTransfer();
    expect(utf8.decode(await conn.client.run('echo embedded')).trim(), 'embedded');
    // 同一条主机记录还可以独立打开 SSH 终端，不能误用 VNC 端口。
    final terminalHost = (await hosts.getByUuid('vnc1'))!.forConnection(HostProtocol.ssh);
    final terminal = TerminalSession(terminalHost, connector, ui);
    await terminal.connect();
    expect(terminal.state, SessionState.connected);
    expect(terminal.host.uuid, vncHost.uuid);
    expect(terminal.host.port, port);
    await terminal.close();
    // 主机指纹记录在 VNC 主机上
    expect((await hosts.getByUuid('vnc1'))!.hostKeyFingerprint, startsWith('SHA256:'));
    await session.close();
    await rfb.close();
  });

  test('经 SSH 写入远程剪贴板（pbcopy），中文不丢失', () async {
    if (!available || !Platform.isMacOS) return markTestSkipped('需要 macOS 本地 sshd');
    await hosts.save(host('direct'));
    final conn = await connector.connect((await hosts.getByUuid('direct'))!, _NoUi());
    // 测试会改写本机剪贴板，结束后恢复
    final backup = (await Process.run('pbpaste', [], stdoutEncoding: utf8)).stdout as String;
    try {
      const text = '远程剪贴板 Remlark ✓\n第二行';
      expect(await SshClipboard.write(conn.client, text), isTrue);
      final local = (await Process.run('pbpaste', [], stdoutEncoding: utf8)).stdout as String;
      expect(local, text);
    } finally {
      final p = await Process.start('pbcopy', []);
      p.stdin.add(utf8.encode(backup));
      await p.stdin.close();
      await p.exitCode;
      conn.close();
    }
  });

  test('经 SSH 读写远程文件剪贴板：写入文件 URL、读回路径与变化计数；上传时按指定名称改名', () async {
    if (!available || !Platform.isMacOS) return markTestSkipped('需要 macOS 本地 sshd');
    await hosts.save(host('direct'));
    final conn = await connector.connect((await hosts.getByUuid('direct'))!, _NoUi());
    final backup = (await Process.run('pbpaste', [], stdoutEncoding: utf8)).stdout as String;
    try {
      final a = File('${dir.path}/剪贴 A.txt')..writeAsStringSync('a');
      final b = File('${dir.path}/b.txt')..writeAsStringSync('b');
      final before = await SshClipboard.read(conn.client);
      final cc = await SshClipboard.writeFiles(conn.client, [a.path, b.path]);
      expect(cc, isNotNull);
      expect(cc, greaterThan(before!.changeCount));
      final pb = await SshClipboard.read(conn.client);
      expect(pb!.changeCount, cc);
      expect(pb.files.map((f) => f.split('/').last), ['剪贴 A.txt', 'b.txt']);
      expect(pb.text, isNull);
      expect(await SshClipboard.frontApp(conn.client), isNotNull);

      // 上传改名（粘贴到已有同名文件的目录）
      final target = Directory('${dir.path}/paste')..createSync();
      final tm = TransferManager(SftpService(conn.client));
      final t = tm.upload(a.path, target.path, asName: '剪贴 A 2.txt');
      expect(await TransferManager.waitAll([t]), isTrue, reason: t.error);
      expect(File('${target.path}/剪贴 A 2.txt').readAsStringSync(), 'a');
      tm.dispose();
    } finally {
      final p = await Process.start('pbcopy', []);
      p.stdin.add(utf8.encode(backup));
      await p.stdin.close();
      await p.exitCode;
      conn.close();
    }
  });

  test('辅助小程序卡住时 10 秒超时并被强制结束，不残留进程', () async {
    if (!available || !Platform.isMacOS) return markTestSkipped('需要 macOS 本地 sshd');
    await hosts.save(host('direct'));
    final conn = await connector.connect((await hosts.getByUuid('direct'))!, _NoUi());
    final name = 'RemlarkFinder-T${DateTime.now().millisecondsSinceEpoch}';
    try {
      final sw = Stopwatch()..start();
      final r = await FinderLocator.query(conn.client, appletName: name, applet: 'delay 30');
      expect(r.error, 'finder.timeout');
      expect(sw.elapsed.inSeconds, lessThan(16));
      final left = await Process.run('pgrep', ['-f', 'Remlark/$name']);
      expect((left.stdout as String).trim(), isEmpty, reason: '超时后应结束小程序');
    } finally {
      final d = '${Platform.environment['HOME']}/Library/Application Support/Remlark';
      for (final f in ['$name.app', '$name.applescript', 'finder-layout.txt']) {
        final e = FileSystemEntity.typeSync('$d/$f');
        if (e == FileSystemEntityType.directory) Directory('$d/$f').deleteSync(recursive: true);
        if (e == FileSystemEntityType.file) File('$d/$f').deleteSync();
      }
      if (Directory(d).existsSync() && Directory(d).listSync().isEmpty) Directory(d).deleteSync();
      conn.close();
    }
  });

  test('Finder 查询链路：远程编译辅助小程序、在图形会话中运行并读回结果', () async {
    if (!available || !Platform.isMacOS) return markTestSkipped('需要 macOS 本地 sshd');
    await hosts.save(host('direct'));
    final conn = await connector.connect((await hosts.getByUuid('direct'))!, _NoUi());
    // 测试小程序不访问 Finder（不触发授权提示），只写入固定布局
    final name = 'RemlarkFinderTest-${DateTime.now().millisecondsSinceEpoch}';
    const applet = '''
set outPath to (POSIX path of (path to home folder)) & "Library/Application Support/Remlark/finder-layout.txt"
set out to "1440,900" & linefeed & "/tmp/desk/" & linefeed & "0,0,100,100" & tab & "/tmp/win/" & linefeed
set f to open for access (POSIX file outPath) with write permission
set eof f to 0
write out to f as «class utf8»
close access f
''';
    try {
      final r = await FinderLocator.query(conn.client, appletName: name, applet: applet);
      expect(r.error, isNull, reason: r.detail);
      expect(r.layout!.desktop, '/tmp/desk/');
      expect(r.layout!.folderAt(const Offset(50, 50), 1440), '/tmp/win/');
    } finally {
      final d = '${Platform.environment['HOME']}/Library/Application Support/Remlark';
      for (final f in ['$name.app', '$name.applescript', 'finder-layout.txt']) {
        final e = FileSystemEntity.typeSync('$d/$f');
        if (e == FileSystemEntityType.directory) Directory('$d/$f').deleteSync(recursive: true);
        if (e == FileSystemEntityType.file) File('$d/$f').deleteSync();
      }
      // 目录为本测试创建且已空时一并删除
      if (Directory(d).existsSync() && Directory(d).listSync().isEmpty) Directory(d).deleteSync();
      conn.close();
    }
  });

  test('传输完成后自动从列表移除（远程桌面浮动传输框），失败任务保留', () async {
    if (!available) return markTestSkipped('sshd not available (macOS / Linux only)');
    final conn = await connector.connect((await hosts.getByUuid('direct'))!, _NoUi());
    final tm = TransferManager(SftpService(conn.client), autoRemoveDoneAfter: const Duration(milliseconds: 200));
    final local = File('${dir.path}/auto.txt')..writeAsStringSync('hi');
    final ok = tm.upload(local.path, dir.path);
    final bad = tm.upload('${dir.path}/not-exist', dir.path);
    while (ok.isActive || bad.isActive) {
      await Future.delayed(const Duration(milliseconds: 50));
    }
    expect(ok.status, TransferStatus.done, reason: ok.error);
    expect(tm.tasks, contains(ok));
    await Future.delayed(const Duration(milliseconds: 400));
    expect(tm.tasks, [bad]);
    tm.dispose();
    conn.close();
  });

  test('SFTP：新建目录、上传（带进度）、列目录、重命名、下载、删除', () async {
    if (!available) return markTestSkipped('sshd not available (macOS / Linux only)');
    final conn = await connector.connect((await hosts.getByUuid('direct'))!, _NoUi());
    final sftp = SftpService(conn.client);
    final remote = '${dir.path}/remote';
    await sftp.mkdir(remote);
    final local = File('${dir.path}/up.bin')..writeAsBytesSync(List.generate(300000, (i) => i % 251));
    final tm = TransferManager(sftp);
    final up = tm.upload(local.path, remote);
    while (up.isActive) {
      await Future.delayed(const Duration(milliseconds: 50));
    }
    expect(up.status, TransferStatus.done, reason: up.error);
    expect(up.transferred, 300000);
    final listed = await sftp.list(remote);
    expect(listed.single.name, 'up.bin');
    expect(listed.single.size, 300000);
    await sftp.rename('$remote/up.bin', '$remote/renamed.bin');
    final dl = Directory('${dir.path}/dl')..createSync();
    final down = tm.download((await sftp.list(remote)).single, dl.path);
    while (down.isActive) {
      await Future.delayed(const Duration(milliseconds: 50));
    }
    expect(down.status, TransferStatus.done, reason: down.error);
    expect(File('${dl.path}/renamed.bin').readAsBytesSync(), local.readAsBytesSync());
    await sftp.delete(remote, isDir: true);
    expect(await sftp.exists(remote), isFalse);
    tm.dispose();
    conn.close();
  });

  test('密钥被拒绝时回退为密码输入（用户取消）', () async {
    if (!available) return markTestSkipped('sshd not available (macOS / Linux only)');
    final other = await KeyUtils.generateEd25519('other');
    await keys.save(
      KeyEntry(
        uuid: 'k2',
        name: 'o',
        keyType: other.keyType,
        privateKey: other.privatePem,
        publicKey: other.publicLine,
        createdAt: 0,
      ),
    );
    await hosts.save(host('badkey').copyWith(keyUuid: () => 'k2'));
    var asked = '';
    final ui = _AskUi((e) => asked = e ?? '');
    await expectLater(connector.connect((await hosts.getByUuid('badkey'))!, ui), throwsA(isA<ConnectCancelled>()));
    expect(asked, 'key_rejected');
  });
}

class _AskUi extends _NoUi {
  _AskUi(this.onAsk);

  final void Function(String?) onAsk;

  @override
  Future<PasswordInput?> askPassword(HostEntry host, {String? error}) async {
    onAsk(error);
    return null;
  }
}
