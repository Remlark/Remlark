import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:dartssh2/dartssh2.dart';

/// 远程命令执行结果
class SshExecResult {
  const SshExecResult(this.exitCode, this.stdout, this.stderr);

  /// 退出码（服务器未报告时为 null）
  final int? exitCode;
  final String stdout;
  final String stderr;

  bool get ok => exitCode == null || exitCode == 0;
}

/// 在远程执行命令：可经 stdin 传入数据（脚本或内容，避免命令行转义问题），收集 UTF-8 输出，支持超时
class SshExec {
  SshExec._();

  /// 执行 [command]；[stdin] 非空时写入后关闭（发送 EOF）。超时抛出 [TimeoutException] 并关闭会话
  static Future<SshExecResult> run(
    SSHClient client,
    String command, {
    String? stdin,
    Duration timeout = const Duration(seconds: 20),
  }) async {
    final session = await client.execute(command).timeout(timeout);
    final out = BytesBuilder(copy: false);
    final err = BytesBuilder(copy: false);
    final outDone = Completer<void>();
    final errDone = Completer<void>();
    session.stdout.listen(out.add, onDone: outDone.complete, onError: (_) => outDone.complete());
    session.stderr.listen(err.add, onDone: errDone.complete, onError: (_) => errDone.complete());
    if (stdin != null) session.stdin.add(Uint8List.fromList(utf8.encode(stdin)));
    await session.stdin.close();
    try {
      await Future.wait([outDone.future, errDone.future, session.done]).timeout(timeout);
    } finally {
      session.close();
    }
    return SshExecResult(
      session.exitCode,
      utf8.decode(out.takeBytes(), allowMalformed: true),
      utf8.decode(err.takeBytes(), allowMalformed: true),
    );
  }
}
