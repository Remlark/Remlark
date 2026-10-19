import 'dart:convert';
import 'dart:io';

import 'package:dartssh2/dartssh2.dart';
import 'package:path/path.dart' as p;

import '../../../utils/platform_utils.dart';
import '../../../utils/shell_utils.dart';
import '../../hosts/host_model.dart';
import '../snippet_action.dart';

/// 特殊快捷指令：系统免密登录。
/// 步骤：
/// 1. 检查本机 ~/.ssh 下的公钥，没有则调用 ssh-keygen 生成 ed25519 密钥
/// 2. 通过当前 SSH 连接把公钥追加到目标（及跳板）主机的 ~/.ssh/authorized_keys
/// 3. 在本机 ~/.ssh/config 写入 Host 别名（含跳板 ProxyJump），之后系统终端可直接 ssh <别名>
class InstallSystemKeyAction extends SnippetAction {
  @override
  bool get showsProgress => true;

  @override
  bool get isAvailable => PlatformUtils.isUnixDesktop;

  @override
  Future<void> run(SnippetContext ctx) async {
    if (!isAvailable) throw UnsupportedError('macOS / Linux only');
    final conn = ctx.session.connection;
    if (conn == null || conn.isClosed) throw StateError('not connected');

    final sshDir = Directory(p.join(PlatformUtils.homeDir(), '.ssh'));
    if (!sshDir.existsSync()) {
      sshDir.createSync(recursive: true);
      await Process.run('chmod', ['700', sshDir.path]);
    }

    // 1. 本机公钥
    final pubKey = await _ensureLocalKey(sshDir, ctx);
    final shown = pubKey.length > 48 ? '${pubKey.substring(0, 48)}...' : pubKey;
    ctx.log('✓ $shown');

    // 2. 安装到跳板与目标主机
    final hops = await ctx.hosts.getByUuids(conn.host.jumpChain);
    final byUuid = {for (final h in hops) h.uuid: h};
    final clients = <(String, SSHClient)>[
      for (var i = 0; i < conn.jumps.length; i++) (byUuid[conn.host.jumpChain[i]]?.name ?? 'jump$i', conn.jumps[i]),
      (conn.host.name, conn.client),
    ];
    for (final (name, client) in clients) {
      ctx.log('→ $name: authorized_keys');
      final q = ShellUtils.quote(pubKey);
      final cmd =
          'mkdir -p ~/.ssh && chmod 700 ~/.ssh && touch ~/.ssh/authorized_keys && '
          'chmod 600 ~/.ssh/authorized_keys && '
          '(grep -qxF $q ~/.ssh/authorized_keys || echo $q >> ~/.ssh/authorized_keys) && echo __OK__';
      final out = utf8.decode(await client.run(cmd), allowMalformed: true);
      if (!out.contains('__OK__')) throw StateError('$name: $out');
      ctx.log('✓ $name');
    }

    // 3. 写入 ~/.ssh/config
    final alias = _alias(conn.host.name);
    final jumps = [
      for (final id in conn.host.jumpChain)
        if (byUuid[id] != null) byUuid[id]!,
    ];
    await _writeConfig(sshDir, conn.host, alias, jumps);
    ctx.log('✓ ~/.ssh/config: Host $alias');
    if (conn.host.proxy.enabled) {
      ctx.log('! proxy settings are not written to ~/.ssh/config');
    }
    ctx.log('');
    ctx.log('ssh $alias');
  }

  /// 获取或生成本机系统密钥，返回公钥行
  Future<String> _ensureLocalKey(Directory sshDir, SnippetContext ctx) async {
    for (final name in ['id_ed25519.pub', 'id_ecdsa.pub', 'id_rsa.pub']) {
      final f = File(p.join(sshDir.path, name));
      if (f.existsSync()) return f.readAsStringSync().trim();
    }
    ctx.log('→ ssh-keygen -t ed25519');
    final keyPath = p.join(sshDir.path, 'id_ed25519');
    final r = await Process.run('ssh-keygen', ['-t', 'ed25519', '-N', '', '-f', keyPath, '-q']);
    if (r.exitCode != 0) throw StateError('ssh-keygen: ${r.stderr}');
    return File('$keyPath.pub').readAsStringSync().trim();
  }

  /// 生成合法的 Host 别名
  String _alias(String name) {
    final a = name.trim().replaceAll(RegExp(r'[^\w.\-]'), '-');
    return a.isEmpty ? 'remlark-host' : a;
  }

  /// 写入或替换 ~/.ssh/config 中由 Remlark 管理的块
  Future<void> _writeConfig(Directory sshDir, HostEntry host, String alias, List<HostEntry> jumps) async {
    final file = File(p.join(sshDir.path, 'config'));
    var content = file.existsSync() ? file.readAsStringSync() : '';
    final begin = '# >>> Remlark ${host.uuid}';
    final end = '# <<< Remlark ${host.uuid}';
    final block = StringBuffer()
      ..writeln(begin)
      ..writeln('Host $alias')
      ..writeln('  HostName ${host.address}')
      ..writeln('  Port ${host.port}');
    if (host.username.isNotEmpty) block.writeln('  User ${host.username}');
    if (jumps.isNotEmpty) {
      final pj = jumps.map((j) => '${j.username.isEmpty ? '' : '${j.username}@'}${j.address}:${j.port}').join(',');
      block.writeln('  ProxyJump $pj');
    }
    block.writeln(end);
    final start = content.indexOf(begin);
    if (start >= 0) {
      final stop = content.indexOf(end, start);
      content = content.replaceRange(start, stop < 0 ? content.length : stop + end.length + 1, '');
    }
    if (content.isNotEmpty && !content.endsWith('\n')) content += '\n';
    content += block.toString();
    await file.writeAsString(content);
    await PlatformUtils.restrictPermissions(file.path);
  }
}
