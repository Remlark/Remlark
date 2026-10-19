import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:remlark/modules/remote_desktop/rdp/rdp_client.dart';

/// RDP 剪贴板端到端测试：使用 native/rdp/test/clip_test_server.c（build_test_server.sh 编译）
void main() {
  final arch = (Process.runSync('uname', ['-m']).stdout as String).trim();
  final os = Platform.isMacOS ? 'macos' : 'linux';
  final server = File('build/native/$os-$arch/clip_test_server');
  final available = !Platform.isWindows && server.existsSync() && RdpClient.isAvailable;

  test('文本双向、本地目录复制到远程、远程文件复制到本地', () async {
    if (!available) return markTestSkipped('clip test server or native library not built');
    final dir = Directory.systemTemp.createTempSync('rmk_clip');
    await Process.run('openssl', [
      'req',
      '-x509',
      '-newkey',
      'rsa:2048',
      '-nodes',
      '-days',
      '1',
      '-subj',
      '/CN=localhost',
      '-keyout',
      '${dir.path}/k.pem',
      '-out',
      '${dir.path}/c.pem',
    ]);
    final port = 34000 + DateTime.now().millisecond;
    final proc = await Process.start(server.absolute.path, ['$port', '${dir.path}/c.pem', '${dir.path}/k.pem']);
    final lines = StreamController<String>.broadcast();
    final seen = <String>[];
    proc.stdout.transform(utf8.decoder).transform(const LineSplitter()).listen((l) {
      seen.add(l);
      lines.add(l);
    });
    proc.stderr.listen((_) {});

    /// 等待服务端输出指定前缀的行
    Future<String> waitLine(String prefix) async {
      final hit = seen.where((l) => l.startsWith(prefix));
      if (hit.isNotEmpty) return hit.first;
      return lines.stream.firstWhere((l) => l.startsWith(prefix)).timeout(const Duration(seconds: 20));
    }

    await waitLine('LISTENING');
    final c = RdpClient();
    final connected = Completer<void>();
    final text = Completer<String>();
    final files = Completer<List<String>>();
    c.onConnected = (_, _) => connected.complete();
    c.onDisconnected = (code, msg) {
      if (!connected.isCompleted) connected.completeError('disconnected $code $msg');
    };
    c.onClipboardText = (t) {
      if (!text.isCompleted) text.complete(t);
    };
    c.onClipboardFiles = (paths) {
      if (!files.isCompleted) files.complete(paths);
    };
    final downloads = Directory(p.join(dir.path, 'downloads'))..createSync();
    c.connect(
      RdpConnectOptions(
        host: '127.0.0.1',
        port: port,
        username: 'u',
        password: 'p',
        width: 800,
        height: 600,
        clipboard: true,
        tempDir: downloads.path,
      ),
    );
    await connected.future.timeout(const Duration(seconds: 20));

    // 1. 远程文本 -> 本地
    expect(await text.future.timeout(const Duration(seconds: 20)), 'server-text-你好');

    // 2. 本地文本 -> 远程
    c.setClipboardText('客户端文本 ok');
    expect(await waitLine('CLIENT_TEXT:'), 'CLIENT_TEXT:客户端文本 ok');

    // 3. 本地目录 -> 远程（远程按需读取文件内容）
    final up = Directory(p.join(dir.path, 'up'))..createSync();
    File(p.join(up.path, 'hello.txt')).writeAsStringSync('hi there');
    c.setClipboardFiles([up.path]);
    expect(await waitLine('CLIENT_FILES:'), 'CLIENT_FILES:up|up\\hello.txt');
    expect(await waitLine('CLIENT_FILE_DATA:'), 'CLIENT_FILE_DATA:hi there');

    // 4. 远程文件 -> 本地（下载到临时目录后通知）
    final got = await files.future.timeout(const Duration(seconds: 20));
    expect(got.map(p.basename).toList()..sort(), ['b.txt', 'folder']);
    final root = p.dirname(got.first);
    expect(File(p.join(root, 'folder', 'a.txt')).readAsStringSync(), 'alpha');
    expect(File(p.join(root, 'b.txt')).readAsStringSync(), 'bravo');

    c.disconnect();
    c.dispose();
    proc.kill();
    dir.deleteSync(recursive: true);
  });
}
