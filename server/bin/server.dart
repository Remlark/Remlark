import 'dart:io';

import 'package:args/args.dart';
import 'package:path/path.dart' as p;
import 'package:remlark_sync_server/remlark_sync_server.dart';
import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as io;

/// 同步服务入口。
/// 用法：dart run bin/server.dart --port 8443 --token <令牌> [--token <令牌2>] [--db 路径] [--cert cert.pem --key key.pem]
/// 令牌也可通过环境变量 REMLARK_SYNC_TOKENS（逗号分隔）提供。
Future<void> main(List<String> args) async {
  final parser = ArgParser()
    ..addOption('host', defaultsTo: '0.0.0.0', help: '监听地址')
    ..addOption('port', defaultsTo: '8443', help: '监听端口')
    ..addOption('db', defaultsTo: 'remlark-sync.sqlite', help: '数据库文件路径')
    ..addMultiOption('token', help: '访问令牌，可多次指定，每个令牌对应独立的数据空间')
    ..addOption('cert', help: 'HTTPS 证书链（PEM）')
    ..addOption('key', help: 'HTTPS 私钥（PEM）')
    ..addFlag('help', abbr: 'h', negatable: false);
  final opts = parser.parse(args);
  if (opts['help'] == true) {
    stdout.writeln(parser.usage);
    return;
  }
  final tokens = <String>{
    ...(opts['token'] as List<String>),
    ...(Platform.environment['REMLARK_SYNC_TOKENS'] ?? '').split(',').map((e) => e.trim()).where((e) => e.isNotEmpty),
  };
  if (tokens.isEmpty) {
    stderr.writeln('至少需要一个访问令牌（--token 或 REMLARK_SYNC_TOKENS）');
    exit(64);
  }
  final dbPath = p.absolute(opts['db'] as String);
  Directory(p.dirname(dbPath)).createSync(recursive: true);
  final db = SyncDatabase(dbPath);
  final api = SyncApi(SyncRepository(db), tokens);
  final handler = const Pipeline().addMiddleware(logRequests()).addHandler(api.handler);

  SecurityContext? tls;
  if (opts['cert'] != null && opts['key'] != null) {
    tls = SecurityContext()
      ..useCertificateChain(opts['cert'] as String)
      ..usePrivateKey(opts['key'] as String);
  } else {
    stderr.writeln('警告：未配置 HTTPS 证书。载荷已在客户端端到端加密，但令牌会以明文传输，建议放在 HTTPS 反向代理之后。');
  }
  final server = await io.serve(
    handler,
    opts['host'] as String,
    int.parse(opts['port'] as String),
    securityContext: tls,
  );
  stdout.writeln(
    'Remlark sync server listening on ${tls == null ? 'http' : 'https'}://${server.address.host}:${server.port}',
  );
  stdout.writeln('database: $dbPath, spaces: ${tokens.length}');
}
