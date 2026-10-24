import '../host_model.dart';
import '../vnc_ssh_config.dart';
import 'host_form.dart';

/// 一个主机下各协议的编辑状态；每个协议保留原有的端口与认证表单。
class HostConnectionForms {
  HostConnectionForms(
    HostEntry? existing,
    HostProtocol initial,
    String? groupUuid,
  ) : existing = existing,
      enabled = existing?.connectionProtocols.toSet() ?? {initial},
      active = existing?.protocol ?? initial,
      osOverride = existing?.extra['osOverride'] as String? {
    for (final protocol in HostProtocol.values) {
      final entry = existing?.connectionProtocols.contains(protocol) == true
          ? existing!.forConnection(protocol)
          : null;
      forms[protocol] = HostForm(entry, protocol, groupUuid);
      if (entry == null && existing != null) {
        forms[protocol]!.name.text = existing.name;
        forms[protocol]!.address.text = existing.address;
        forms[protocol]!.groupUuid = existing.groupUuid;
        forms[protocol]!.note.text = existing.note;
        forms[protocol]!.syncEnabled = existing.syncEnabled;
      }
    }
  }

  final HostEntry? existing;
  final Set<HostProtocol> enabled;
  final Map<HostProtocol, HostForm> forms = {};
  HostProtocol active;
  String? osOverride;

  HostForm get current => forms[active]!;

  /// 切换编辑视图时，同步主机公共字段，保留各协议自身的端口和凭据。
  void select(HostProtocol protocol) {
    final source = current;
    final target = forms[protocol]!;
    target.name.text = source.name.text;
    target.address.text = source.address.text;
    target.groupUuid = source.groupUuid;
    target.note.text = source.note.text;
    target.syncEnabled = source.syncEnabled;
    active = protocol;
  }

  /// 保存前检查所有已开启协议的配置。
  String? validate() {
    for (final protocol in enabled) {
      final form = forms[protocol]!;
      form.address.text = current.address.text;
      final error = form.validate();
      if (error != null &&
          !(protocol == HostProtocol.vnc &&
              enabled.contains(HostProtocol.ssh) &&
              (error.startsWith('vnc.ssh.') || error == 'auth.key.required'))) {
        return error;
      }
      if (protocol == HostProtocol.ssh &&
          form.authType == AuthType.key &&
          form.keyUuid == null) {
        return 'auth.key.required';
      }
    }
    return null;
  }

  /// 生成单条主机记录，附加协议保存为独立连接配置。
  HostEntry build() {
    final source = current;
    for (final form in forms.values) {
      form.name.text = source.name.text;
      form.address.text = source.address.text;
      form.groupUuid = source.groupUuid;
      form.note.text = source.note.text;
      form.syncEnabled = source.syncEnabled;
    }
    final primary = enabled.contains(HostProtocol.vnc)
        ? HostProtocol.vnc
        : enabled.contains(HostProtocol.ssh)
        ? HostProtocol.ssh
        : HostProtocol.rdp;
    // VNC 的 SSH 扩展继续负责文件与剪贴板能力；连接参数由 SSH 表单单独保存。
    final vncForm = forms[HostProtocol.vnc]!;
    if (enabled.contains(HostProtocol.vnc) &&
        vncForm.vncSsh.enabled != enabled.contains(HostProtocol.ssh)) {
      vncForm.setSshEnabled(enabled.contains(HostProtocol.ssh));
    }
    final built = {for (final p in enabled) p: forms[p]!.build()};
    var base = built[primary]!;
    final profiles = <String, dynamic>{};
    for (final item in built.entries) {
      if (item.key == primary) continue;
      final json = item.value.toPortableJson();
      json.remove('uuid');
      json.remove('name');
      json.remove('address');
      json.remove('createdAt');
      json.remove('updatedAt');
      if (item.value.hostKeyFingerprint != null) {
        json['hostKeyFingerprint'] = item.value.hostKeyFingerprint;
      }
      // 附加配置只保存该协议本身的数据，防止多层嵌套。
      final extra = Map<String, dynamic>.from(json['extra'] as Map);
      extra.remove('connections');
      json['extra'] = extra;
      profiles[item.key.name] = json;
    }
    final extra = Map<String, dynamic>.from(base.extra);
    extra.remove('connections');
    if (osOverride == null) {
      extra.remove('osOverride');
    } else {
      extra['osOverride'] = osOverride;
    }
    if (profiles.isNotEmpty) extra['connections'] = profiles;
    if (primary == HostProtocol.vnc) {
      final ssh = built[HostProtocol.ssh];
      if (ssh != null) {
        VncSshConfig(
          enabled: true,
          port: ssh.port,
          authType: ssh.authType,
          keyUuid: ssh.keyUuid,
        ).writeTo(extra);
      }
    }
    base = base.copyWith(
      uuid: existing?.uuid,
      groupUuid: () => source.groupUuid,
      note: source.note.text,
      syncEnabled: source.syncEnabled,
      createdAt: existing?.createdAt,
      osId: () => existing?.osId,
      osName: () => existing?.osName,
      hostKeyFingerprint: () =>
          existing?.protocol == primary &&
              existing?.address == source.address.text.trim()
          ? existing?.hostKeyFingerprint
          : null,
      extra: extra,
    );
    return base;
  }

  /// 释放所有输入控制器。
  void dispose() {
    for (final form in forms.values) {
      form.dispose();
    }
  }
}
