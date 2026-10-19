import 'dart:async';
import 'dart:convert';

import 'package:dartssh2/dartssh2.dart';

import '../hosts/host_model.dart';
import '../hosts/host_repository.dart';
import '../keys/key_repository.dart';
import '../keys/key_utils.dart';
import 'os_detector.dart';
import 'proxy_socket.dart';
import 'ssh_interaction.dart';

/// 已建立的 SSH 连接（含跳板链上的中间连接）
class SshConnection {
  SshConnection(this.host, this.client, this.jumps);

  final HostEntry host;

  /// 目标主机的客户端
  final SSHClient client;

  /// 跳板链上的客户端，按连接顺序
  final List<SSHClient> jumps;

  /// 连接是否已关闭
  bool get isClosed => client.isClosed;

  /// 关闭连接：先关目标，再逆序关闭跳板
  void close() {
    client.close();
    for (final j in jumps.reversed) {
      j.close();
    }
  }
}

/// SSH 连接器：负责代理、跳板链、认证流程（含密码错误重试）、指纹校验与系统探测
class SshConnector {
  SshConnector(this._hosts, this._keys);

  final HostRepository _hosts;
  final KeyRepository _keys;

  /// 密码错误时最多重试的次数
  static const _maxAttempts = 5;

  /// 连接到 [target]，必要时通过跳板链与代理
  Future<SshConnection> connect(HostEntry target, SshInteraction ui) async {
    final chain = await _resolveChain(target);
    final clients = <SSHClient>[];
    try {
      final hops = [...chain, target];
      for (var i = 0; i < hops.length; i++) {
        final hop = hops[i];
        ui.onProgress(hop.name);
        Future<SSHSocket> Function() socketFactory;
        if (i == 0) {
          // 第一跳：使用自身代理配置，没有则使用目标主机的代理配置
          final proxy = hop.proxy.enabled ? hop.proxy : target.proxy;
          socketFactory = () => ProxyConnector.connect(hop.address, hop.port, proxy);
        } else {
          final prev = clients.last;
          socketFactory = () => prev.forwardLocal(hop.address, hop.port);
        }
        clients.add(await _authenticate(hop, socketFactory, ui));
      }
    } catch (e) {
      for (final c in clients.reversed) {
        c.close();
      }
      rethrow;
    }
    unawaited(_hosts.touchConnected(target.uuid));
    return SshConnection(target, clients.last, clients.sublist(0, clients.length - 1));
  }

  /// 后台探测远程系统并写入数据库，返回探测结果
  Future<OsInfo?> detectOs(SshConnection conn) async {
    final info = await OsDetector.detect(conn.client);
    if (info != null && (info.id != conn.host.osId || info.name != conn.host.osName)) {
      await _hosts.updateOs(conn.host.uuid, info.id, info.name);
    }
    return info;
  }

  /// 解析跳板链，检测循环引用
  Future<List<HostEntry>> _resolveChain(HostEntry target) async {
    if (target.jumpChain.isEmpty) return [];
    final hosts = await _hosts.getByUuids(target.jumpChain);
    final byUuid = {for (final h in hosts) h.uuid: h};
    final result = <HostEntry>[];
    for (final id in target.jumpChain) {
      if (id == target.uuid) throw StateError('jump chain contains target itself');
      final h = byUuid[id];
      if (h == null) throw StateError('jump host not found: $id');
      result.add(h);
    }
    return result;
  }

  /// 对单个主机进行认证。流程：
  /// 1. 密码认证：有保存的密码直接用；否则弹框输入（可勾选记住）
  /// 2. 密码错误：重新弹框并提示错误，最多 [_maxAttempts] 次
  /// 3. 密钥认证：加载密钥（加密私钥需输入口令）；密钥被拒绝时回退为密码输入
  /// 4. keyboard-interactive：有密码时自动应答，否则逐项询问用户
  Future<SSHClient> _authenticate(HostEntry hop, Future<SSHSocket> Function() socketFactory, SshInteraction ui) async {
    String? password = hop.savePassword ? hop.password : null;
    var remember = false;
    String? error;
    var mode = hop.authType;
    List<SSHKeyPair>? identities;

    if (mode == AuthType.key) {
      identities = await _loadIdentities(hop, ui);
      if (identities == null) mode = AuthType.password;
    }

    for (var attempt = 0; attempt < _maxAttempts; attempt++) {
      if (mode == AuthType.password && password == null) {
        final input = await ui.askPassword(hop, error: error);
        if (input == null) throw ConnectCancelled();
        password = input.password;
        remember = input.remember;
      }
      final socket = await socketFactory();
      final client = SSHClient(
        socket,
        username: hop.username,
        identities: mode == AuthType.key ? identities : null,
        onPasswordRequest: mode == AuthType.password ? () => password : null,
        onUserInfoRequest: mode == AuthType.key ? null : (req) => _answerKeyboard(hop, req, password, ui),
        onVerifyHostKey: (type, fp) => _verifyHostKey(hop, type, fp, ui),
        keepAliveInterval: const Duration(seconds: 20),
        handshakeTimeout: const Duration(seconds: 20),
        authTimeout: const Duration(seconds: 120),
      );
      try {
        await client.authenticated;
        if (remember && password != null) {
          await _hosts.updatePassword(hop.uuid, password, true);
        }
        return client;
      } on SSHAuthError {
        client.close();
        if (mode == AuthType.key) {
          // 密钥被拒绝，回退为密码登录
          mode = AuthType.password;
          error = 'key_rejected';
        } else {
          error = 'wrong_password';
        }
        password = null;
      } catch (e) {
        client.close();
        rethrow;
      }
    }
    throw SSHAuthFailError('too many attempts');
  }

  /// 加载主机配置的密钥，加密私钥会请求口令；未配置密钥返回 null
  Future<List<SSHKeyPair>?> _loadIdentities(HostEntry hop, SshInteraction ui) async {
    final keyId = hop.keyUuid;
    if (keyId == null) return null;
    final key = await _keys.get(keyId);
    if (key == null) return null;
    var passphrase = key.passphrase;
    if (!KeyUtils.isEncrypted(key.privateKey)) {
      return KeyUtils.parse(key.privateKey);
    }
    String? error;
    for (var i = 0; i < _maxAttempts; i++) {
      if (passphrase == null || passphrase.isEmpty) {
        passphrase = await ui.askPassphrase(hop, error: error);
        if (passphrase == null) throw ConnectCancelled();
      }
      try {
        return KeyUtils.parse(key.privateKey, passphrase);
      } catch (_) {
        error = 'wrong_passphrase';
        passphrase = null;
      }
    }
    throw ConnectCancelled();
  }

  /// keyboard-interactive：若提示为密码且已知密码则自动应答
  Future<List<String>?> _answerKeyboard(
    HostEntry hop,
    SSHUserInfoRequest req,
    String? password,
    SshInteraction ui,
  ) async {
    if (req.prompts.isEmpty) return [];
    if (password != null &&
        req.prompts.length == 1 &&
        !req.prompts.first.echo &&
        req.prompts.first.promptText.toLowerCase().contains('password')) {
      return [password];
    }
    return ui.keyboardInteractive(hop, req);
  }

  /// 指纹校验：首次连接自动记录（accept-new），之后不一致需用户确认
  Future<bool> _verifyHostKey(HostEntry hop, String type, List<int> fingerprint, SshInteraction ui) async {
    final fp = utf8.decode(fingerprint);
    final old = hop.hostKeyFingerprint;
    if (old == null || old.isEmpty) {
      await _hosts.updateFingerprint(hop.uuid, fp);
      return true;
    }
    if (old == fp) return true;
    final ok = await ui.confirmHostKeyChanged(hop, type, old, fp);
    if (ok) await _hosts.updateFingerprint(hop.uuid, fp);
    return ok;
  }
}
