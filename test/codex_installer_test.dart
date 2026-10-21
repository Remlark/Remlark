import 'dart:convert';
import 'dart:io';

import 'package:cryptography/cryptography.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:remlark/modules/ai/codex/codex_environment.dart';
import 'package:remlark/modules/ai/codex/codex_installer.dart';
import 'package:remlark/modules/ai/codex/codex_types.dart';
import 'package:remlark/modules/ai/codex/platform/codex_platform.dart';

import 'helpers/platform_tools.dart';

/// 测试用平台：固定的发布包名称；Windows 上用 .cmd 脚本模拟可执行文件，其余平台用 sh 脚本
class _TestPlatform implements CodexPlatform {
  @override
  String? get releaseAsset => 'codex-package-test.tar.gz';

  @override
  String get executableName => Platform.isWindows ? 'codex.cmd' : 'codex';

  @override
  String get codeModeHostName => Platform.isWindows ? 'codex-code-mode-host.cmd' : 'codex-code-mode-host';
}

/// 生成假的运行包（主程序输出版本号，执行工具可运行，附 codex-package.json），返回 tar.gz 字节
Future<List<int>> _package(Directory tmp, String version) async {
  final platform = _TestPlatform();
  final src = Directory(p.join(tmp.path, 'pkg-$version'));
  await Directory(p.join(src.path, 'bin')).create(recursive: true);
  final exe = File(p.join(src.path, 'bin', platform.executableName));
  final host = File(p.join(src.path, 'bin', platform.codeModeHostName));
  if (Platform.isWindows) {
    exe.writeAsStringSync('@echo codex-cli $version\r\n');
    host.writeAsStringSync('@exit /b 0\r\n');
  } else {
    exe.writeAsStringSync('#!/bin/sh\necho "codex-cli $version"\n');
    host.writeAsStringSync('#!/bin/sh\nexit 0\n');
    await Process.run('chmod', ['755', exe.path, host.path]);
  }
  File(p.join(src.path, 'codex-package.json')).writeAsStringSync(jsonEncode({'version': version}));
  final archive = p.join(tmp.path, 'pkg-$version.tar.gz');
  final r = await Process.run(systemTar(), ['-czf', archive, '-C', src.path, '.']);
  expect(r.exitCode, 0, reason: '${r.stderr}');
  return File(archive).readAsBytes();
}

void main() {
  late Directory tmp;
  late HttpServer server;
  late Map<String, List<int>> files;
  late Map<String, dynamic> release;

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('rmk-codex-');
    files = {};
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((req) async {
      if (req.uri.path == '/latest') {
        req.response.write(jsonEncode(release));
      } else if (files[req.uri.path] case final bytes?) {
        req.response.contentLength = bytes.length;
        req.response.add(bytes);
      } else {
        req.response.statusCode = 404;
      }
      await req.response.close();
    });
  });

  tearDown(() async {
    await server.close(force: true);
    await tmp.delete(recursive: true);
  });

  /// 发布 [version]：[digest] 为 null 时使用正确的 SHA-256
  Future<void> publish(String version, {String? digest}) async {
    final bytes = await _package(tmp, version);
    files['/dl/$version.tar.gz'] = bytes;
    final sha = (await Sha256().hash(bytes)).bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
    release = {
      'tag_name': 'rust-v$version',
      'assets': [
        {
          'name': 'codex-package-test.tar.gz',
          'browser_download_url': 'http://127.0.0.1:${server.port}/dl/$version.tar.gz',
          'size': bytes.length,
          'digest': 'sha256:${digest ?? sha}',
        },
      ],
    };
  }

  test('安装、升级与校验失败时保留旧版本', () async {
    final env = CodexEnvironment(p.join(tmp.path, 'codex'), _TestPlatform());
    CodexInstaller installer() => CodexInstaller(env, latestReleaseUrl: 'http://127.0.0.1:${server.port}/latest');

    await publish('0.1.0');
    var i = installer();
    final r1 = await i.latestRelease();
    expect(r1.version, '0.1.0');
    expect(await i.install(r1), '0.1.0');
    expect(env.installed, isTrue);
    expect(env.version, '0.1.0');
    i.dispose();

    await publish('0.2.0');
    i = installer();
    var replaced = false;
    await i.install(await i.latestRelease(), beforeReplace: () async => replaced = true);
    expect(replaced, isTrue);
    expect(env.version, '0.2.0');
    i.dispose();

    // 校验值不符：不替换已安装的版本，也不留下临时目录
    await publish('0.3.0', digest: '0' * 64);
    i = installer();
    await expectLater(i.install(await i.latestRelease()), throwsA(isA<CodexException>()));
    expect(env.version, '0.2.0');
    expect(Directory(env.root).listSync().map((e) => p.basename(e.path)).where((n) => n.startsWith('.staging-')), isEmpty);

    await i.uninstall();
    expect(env.installed, isFalse);
    i.dispose();
  });

  test('采用临时目录中的登录：只替换凭据文件，删除临时目录，保留 Agent 原有数据', () async {
    final env = CodexEnvironment(p.join(tmp.path, 'codex'), _TestPlatform());
    final staging = CodexEnvironment.newStagingHomeId();
    await env.prepare(staging);
    File(p.join(env.homeDir(staging), 'auth.json')).writeAsStringSync('{"new":true}');
    await env.prepare('agent');
    File(p.join(env.homeDir('agent'), 'auth.json')).writeAsStringSync('{"old":true}');
    File(p.join(env.homeDir('agent'), 'state.sqlite')).writeAsStringSync('keep');

    await env.adoptLogin(staging, 'agent');
    expect(File(p.join(env.homeDir('agent'), 'auth.json')).readAsStringSync(), '{"new":true}');
    expect(File(p.join(env.homeDir('agent'), 'state.sqlite')).readAsStringSync(), 'keep');
    expect(Directory(env.homeDir(staging)).existsSync(), isFalse);
  });
}
