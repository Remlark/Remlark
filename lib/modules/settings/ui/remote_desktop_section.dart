import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../l10n/app_localizations.dart';
import '../../remote_desktop/rdp/rdp_client.dart';
import '../../remote_desktop/rdp/rdp_h264.dart';
import '../settings_controller.dart';
import 'settings_card.dart';

/// 远程桌面设置：RDP H.264 硬件解码开关，说明中显示本机硬件解码是否可用
class RemoteDesktopSection extends StatelessWidget {
  const RemoteDesktopSection({super.key});

  @override
  Widget build(BuildContext context) {
    final s = context.watch<SettingsController>();
    // 原生库缺失时不探测；探测结果由 RdpH264Support 缓存，只在首次打开时创建一次硬件设备
    final h264 = RdpClient.isAvailable ? RdpH264Support.probe() : null;
    final supported = h264 != null && h264.decoder && h264.hardware;
    final status = h264 == null
        ? context.tr('settings.rdp_hwdec.missing')
        : supported
        ? context.tr('settings.rdp_hwdec.available', {'name': h264.hwName})
        : context.tr('settings.rdp_hwdec.unavailable');
    return SettingsCard(
      title: context.tr('settings.remote_desktop'),
      description: context.tr('settings.remote_desktop.desc'),
      children: [
        SettingsRow(
          label: context.tr('settings.rdp_hwdec'),
          description: '${context.tr('settings.rdp_hwdec.desc')}\n$status',
          // 本机不支持时开关不可操作（保留已保存的选择，换到支持的机器上仍生效）
          child: Switch(
            value: supported && s.rdpHardwareDecode,
            onChanged: supported ? s.setRdpHardwareDecode : null,
          ),
        ),
      ],
    );
  }
}
