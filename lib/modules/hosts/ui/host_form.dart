import 'package:flutter/material.dart';

import '../../../utils/id_utils.dart';
import '../host_model.dart';
import '../vnc_ssh_config.dart';

/// 主机编辑表单状态：集中管理所有输入控制器，供各编辑分区共享
class HostForm extends ChangeNotifier {
  HostForm(HostEntry? e, HostProtocol protocol, String? groupUuid)
    : existing = e,
      protocol = e?.protocol ?? protocol,
      groupUuid = e?.groupUuid ?? groupUuid,
      name = TextEditingController(text: e?.name ?? ''),
      address = TextEditingController(text: e?.address ?? ''),
      port = TextEditingController(text: '${e?.port ?? (e?.protocol ?? protocol).defaultPort}'),
      username = TextEditingController(text: e?.username ?? ''),
      password = TextEditingController(text: e?.password ?? ''),
      note = TextEditingController(text: e?.note ?? ''),
      proxyHost = TextEditingController(text: e?.proxy.host ?? ''),
      proxyPort = TextEditingController(text: (e?.proxy.port ?? 0) == 0 ? '' : '${e!.proxy.port}'),
      proxyUser = TextEditingController(text: e?.proxy.username ?? ''),
      proxyPass = TextEditingController(text: e?.proxy.password ?? ''),
      domain = TextEditingController(text: e?.extra['domain'] as String? ?? ''),
      width = TextEditingController(text: '${e?.extra['width'] ?? ''}'),
      height = TextEditingController(text: '${e?.extra['height'] ?? ''}'),
      authType = e?.authType ?? AuthType.password,
      savePassword = e?.savePassword ?? true,
      keyUuid = e?.keyUuid,
      jumpChain = List.of(e?.jumpChain ?? const []),
      proxyType = e?.proxy.type ?? ProxyType.none,
      proxyUuid = e?.proxyUuid,
      clipboard = e?.extra['clipboard'] != false,
      vncSsh = e == null ? const VncSshConfig() : (VncSshConfig.fromExtra(e.extra) ?? const VncSshConfig()),
      syncEnabled = e?.syncEnabled ?? false {
    sshPort = TextEditingController(text: '${vncSsh.port}');
  }

  final HostEntry? existing;
  HostProtocol protocol;
  String? groupUuid;
  final TextEditingController name, address, port, username, password, note;
  final TextEditingController proxyHost, proxyPort, proxyUser, proxyPass;
  final TextEditingController domain, width, height;
  AuthType authType;
  bool savePassword;
  String? keyUuid;
  List<String> jumpChain;
  ProxyType proxyType;
  String? proxyUuid;

  /// 选用共享代理时同步表单快照，便于旧载荷和协议切换继续兼容。
  void selectProxy(String? uuid, ProxyConfig config) {
    proxyUuid = uuid;
    proxyType = config.type;
    proxyHost.text = config.host;
    proxyPort.text = '${config.port}';
    proxyUser.text = config.username;
    proxyPass.text = config.password ?? '';
    notifyListeners();
  }
  bool clipboard;
  bool syncEnabled;

  /// VNC 主机内置的 SSH 配置（文件传输与剪贴板）
  VncSshConfig vncSsh;
  late final TextEditingController sshPort;

  /// 无法无损合并的旧关联继续兼容，用户开启内置 SSH 后才替换。
  bool preserveLegacySsh = false;

  /// 旧版“关联独立 SSH 主机”迁移为内置配置：沿用其端口、认证方式与密钥（保存时移除旧字段）
  void migrateLegacySsh(HostEntry? linked) {
    final e = existing;
    if (e == null || e.legacyTransferHost == null || VncSshConfig.fromExtra(e.extra) != null) return;
    // 不同端点、凭据或跳板代理不能直接压缩为共用账户，否则编辑名称也会破坏连接。
    preserveLegacySsh = true;
    if (linked == null ||
        linked.protocol != HostProtocol.ssh ||
        linked.address != e.address ||
        linked.username != e.username ||
        linked.jumpChain.isNotEmpty ||
        linked.proxy.enabled ||
        linked.authType == AuthType.keyboard ||
        (linked.authType == AuthType.password &&
            (linked.password != e.password || linked.savePassword != e.savePassword))) {
      return;
    }
    preserveLegacySsh = false;
    vncSsh = VncSshConfig(
      enabled: true,
      port: linked.port,
      authType: linked.authType == AuthType.key ? AuthType.key : AuthType.password,
      keyUuid: linked.keyUuid,
    );
    sshPort.text = '${linked.port}';
  }

  /// 修改后刷新界面
  void update(VoidCallback fn) {
    fn();
    notifyListeners();
  }

  String _vncPort = '5900';

  /// VNC 中启用或关闭 SSH，保留参数供再次开启，显式选择替换旧关联。
  void setSshEnabled(bool enabled) {
    vncSsh = vncSsh.copyWith(enabled: enabled);
    preserveLegacySsh = false;
    notifyListeners();
  }

  /// 切换主协议时保留端口和 SSH 认证；已有 SSH 配置带入 VNC。
  void setProtocol(HostProtocol p) {
    if (p == protocol) return;
    if (protocol == HostProtocol.ssh) {
      sshPort.text = port.text;
      vncSsh = vncSsh.copyWith(enabled: true, authType: authType, keyUuid: () => keyUuid);
    } else if (protocol == HostProtocol.vnc) {
      _vncPort = port.text;
    }
    protocol = p;
    if (p == HostProtocol.ssh) {
      port.text = sshPort.text;
      authType = vncSsh.authType;
      keyUuid = vncSsh.keyUuid;
    } else {
      port.text = p == HostProtocol.vnc ? _vncPort : '3389';
    }
    notifyListeners();
  }

  /// 校验连接参数，返回可直接翻译的错误键。
  String? validate() {
    if (address.text.trim().isEmpty) return 'host.address.required';
    final hostPort = int.tryParse(port.text.trim());
    if (hostPort == null || hostPort < 1 || hostPort > 65535) return 'host.port.invalid';
    if (protocol == HostProtocol.vnc && vncSsh.enabled) {
      final value = int.tryParse(sshPort.text.trim());
      if (value == null || value < 1 || value > 65535) return 'vnc.ssh.port.invalid';
      if (username.text.trim().isEmpty) return 'vnc.ssh.username.required';
      if (vncSsh.authType == AuthType.key && vncSsh.keyUuid == null) return 'auth.key.required';
    }
    return null;
  }

  /// 构造主机实体
  HostEntry build() {
    final now = DateTime.now().millisecondsSinceEpoch;
    final e = existing;
    final extra = <String, dynamic>{...?e?.extra};
    if (protocol == HostProtocol.rdp) {
      extra['domain'] = domain.text.trim();
      final w = int.tryParse(width.text.trim());
      final h = int.tryParse(height.text.trim());
      if (w != null && h != null) {
        extra['width'] = w;
        extra['height'] = h;
      } else {
        extra.remove('width');
        extra.remove('height');
      }
      extra.remove('fullscreen');
      extra['clipboard'] = clipboard;
    }
    if (protocol == HostProtocol.vnc) {
      if (!preserveLegacySsh || vncSsh.enabled) {
        vncSsh.copyWith(port: int.tryParse(sshPort.text.trim()) ?? 22).writeTo(extra);
        // 仅在完成无损迁移或用户主动配置内置 SSH 后移除旧关联。
        extra.remove('transferHost');
      }
      // 已取消固定接收目录：上传目标由拖放位置决定
      extra.remove('transferDir');
    }
    if (protocol != HostProtocol.vnc) {
      extra.remove('ssh');
      extra.remove('transferHost');
    }
    final name = this.name.text.trim().isEmpty ? address.text.trim() : this.name.text.trim();
    return HostEntry(
      uuid: e?.uuid ?? IdUtils.newId(),
      protocol: protocol,
      name: name,
      groupUuid: groupUuid,
      address: address.text.trim(),
      port: int.tryParse(port.text.trim()) ?? protocol.defaultPort,
      username: username.text.trim(),
      authType: protocol == HostProtocol.ssh ? authType : AuthType.password,
      password: password.text.isEmpty ? null : password.text,
      savePassword: savePassword && password.text.isNotEmpty,
      keyUuid: authType == AuthType.key ? keyUuid : null,
      jumpChain: protocol == HostProtocol.ssh || vncSsh.enabled ? jumpChain : const [],
      proxyUuid: protocol != HostProtocol.vnc || vncSsh.enabled ? proxyUuid : null,
      proxy: protocol != HostProtocol.vnc || vncSsh.enabled
          ? ProxyConfig(
              type: proxyType,
              host: proxyHost.text.trim(),
              port: int.tryParse(proxyPort.text.trim()) ?? 0,
              username: proxyUser.text.trim(),
              password: proxyPass.text.isEmpty ? null : proxyPass.text,
            )
          : const ProxyConfig(),
      osId: e?.osId,
      osName: e?.osName,
      hostKeyFingerprint: e?.address == address.text.trim() ? e?.hostKeyFingerprint : null,
      extra: extra,
      note: note.text,
      syncEnabled: e?.syncEnabled ?? false,
      syncedAt: e?.syncedAt,
      updatedAt: now,
      createdAt: e?.createdAt ?? now,
      lastConnectedAt: e?.lastConnectedAt,
    );
  }

  @override
  void dispose() {
    for (final c in [
      name,
      address,
      port,
      username,
      password,
      note,
      proxyHost,
      proxyPort,
      proxyUser,
      proxyPass,
      domain,
      width,
      height,
      sshPort,
    ]) {
      c.dispose();
    }
    super.dispose();
  }
}
