import 'package:flutter/material.dart';

import '../../../utils/id_utils.dart';
import '../host_model.dart';

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
      transferDir = TextEditingController(text: e?.extra['transferDir'] as String? ?? '~/Desktop'),
      authType = e?.authType ?? AuthType.password,
      savePassword = e?.savePassword ?? true,
      keyUuid = e?.keyUuid,
      jumpChain = List.of(e?.jumpChain ?? const []),
      proxyType = e?.proxy.type ?? ProxyType.none,
      clipboard = e?.extra['clipboard'] != false,
      transferHost = e?.extra['transferHost'] as String?,
      syncEnabled = e?.syncEnabled ?? false;

  final HostEntry? existing;
  HostProtocol protocol;
  String? groupUuid;
  final TextEditingController name, address, port, username, password, note;
  final TextEditingController proxyHost, proxyPort, proxyUser, proxyPass;
  final TextEditingController domain, width, height, transferDir;
  AuthType authType;
  bool savePassword;
  String? keyUuid;
  List<String> jumpChain;
  ProxyType proxyType;
  bool clipboard;
  String? transferHost;
  bool syncEnabled;

  /// 修改后刷新界面
  void update(VoidCallback fn) {
    fn();
    notifyListeners();
  }

  /// 切换协议时同步默认端口
  void setProtocol(HostProtocol p) {
    final oldDefault = '${protocol.defaultPort}';
    protocol = p;
    if (port.text.isEmpty || port.text == oldDefault) port.text = '${p.defaultPort}';
    notifyListeners();
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
      if (transferHost != null) {
        extra['transferHost'] = transferHost;
      } else {
        extra.remove('transferHost');
      }
      extra['transferDir'] = transferDir.text.trim();
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
      jumpChain: protocol == HostProtocol.ssh ? jumpChain : const [],
      proxy: protocol != HostProtocol.vnc
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
      transferDir,
    ]) {
      c.dispose();
    }
    super.dispose();
  }
}
