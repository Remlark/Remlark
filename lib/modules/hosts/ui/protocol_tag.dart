import 'package:flutter/material.dart';

import '../../../app/theme/app_palette.dart';
import '../../../ui_kit/tags.dart';
import '../host_model.dart';
import '../vnc_ssh_config.dart';

/// 协议标签：SSH / RDP / VNC / SFTP 使用调色板中各自的协议色
class ProtocolTag extends StatelessWidget {
  const ProtocolTag(this.label, {super.key, this.small = false});

  /// 由主机协议构造
  ProtocolTag.of(HostProtocol protocol, {Key? key, bool small = false})
    : this(protocol.name.toUpperCase(), key: key, small: small);

  /// 标签文本（SSH / RDP / VNC / SFTP）
  final String label;
  final bool small;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final color = switch (label) {
      'RDP' => p.protoRdp,
      'VNC' => p.protoVnc,
      'SFTP' => p.protoSftp,
      _ => p.protoSsh,
    };
    return Tag(label, color: color, small: small);
  }
}

/// 按主机实际支持的协议并排显示独立标签，卡片与列表共用。
class HostProtocolTags extends StatelessWidget {
  const HostProtocolTags({super.key, required this.host, this.small = false});

  final HostEntry host;
  final bool small;

  /// 每种协议保留自身颜色，相邻标签间距为 6px。
  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    spacing: 6,
    children: [for (final protocol in host.connectionProtocols) ProtocolTag.of(protocol, small: small)],
  );
}
