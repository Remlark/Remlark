import 'package:flutter/material.dart';

import '../../../app/theme/app_palette.dart';
import '../../../app/theme/app_theme.dart';
import '../../../l10n/app_localizations.dart';
import '../../../ui_kit/buttons.dart';
import '../../../utils/format_utils.dart';
import '../../hosts/host_model.dart';
import '../../hosts/vnc_ssh_config.dart';
import '../../hosts/ui/host_card.dart';
import '../../hosts/ui/os_icon.dart';

/// 工作区紧凑卡片：名称、端点、分组与最近时间；各协议使用明确的独立入口。
class WorkspaceHostCard extends StatefulWidget {
  const WorkspaceHostCard({
    super.key,
    required this.host,
    required this.groupName,
    required this.onAction,
  });

  final HostEntry host;
  final String groupName;
  final ValueChanged<HostAction> onAction;

  /// 创建悬停状态，沿用现有主机菜单与连接按钮。
  @override
  State<WorkspaceHostCard> createState() => _WorkspaceHostCardState();
}

class _WorkspaceHostCardState extends State<WorkspaceHostCard> {
  bool _hover = false;

  /// 更多菜单与右键共用同一入口，避免工作区出现不同的主机操作规则。
  void _showMenu(Offset position) {
    showHostMenu(context, widget.host, position, widget.onAction);
  }

  /// 卡片按固定高度排版，长名称与端点提供完整提示并在行内省略。
  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final host = widget.host;
    final time = host.lastConnectedAt;
    final timeText = time == null
        ? context.tr('host.never_connected')
        : FormatUtils.dateTime(DateTime.fromMillisecondsSinceEpoch(time));
    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        onDoubleTap: host.connectionProtocols.length == 1
            ? () => widget.onAction(HostAction.connect)
            : null,
        onSecondaryTapUp: (details) => _showMenu(details.globalPosition),
        child: Container(
          padding: const EdgeInsets.fromLTRB(16, 12, 12, 12),
          decoration: BoxDecoration(
            color: p.panel,
            borderRadius: BorderRadius.circular(AppSizes.radiusLarge),
            border: Border.all(color: _hover ? p.accent : p.border),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  OsIcon(host: host, size: 34),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Tooltip(
                          message: host.name,
                          child: Text(
                            host.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                              color: p.text,
                            ),
                          ),
                        ),
                        const SizedBox(height: 4),
                        Tooltip(
                          message: host.endpoint,
                          child: Text(
                            host.endpoint,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 13,
                              fontFamily: 'monospace',
                              color: p.textMuted,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  Builder(
                    builder: (buttonContext) => GhostIconButton(
                      icon: Icons.more_horiz,
                      tooltip: context.tr('common.more'),
                      size: 28,
                      onPressed: () {
                        final box =
                            buttonContext.findRenderObject() as RenderBox;
                        _showMenu(
                          box.localToGlobal(box.size.bottomLeft(Offset.zero)),
                        );
                      },
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Padding(
                padding: const EdgeInsets.only(left: 46),
                child: Text(
                  widget.groupName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 12, color: p.textMuted),
                ),
              ),
              const Spacer(),
              Row(
                children: [
                  Icon(Icons.history, size: 14, color: p.textFaint),
                  const SizedBox(width: 5),
                  Expanded(
                    child: Tooltip(
                      message:
                          '${context.tr('host.last_connected')}: $timeText',
                      child: Text(
                        time == null
                            ? timeText
                            : FormatUtils.relativeDateTime(
                                DateTime.fromMillisecondsSinceEpoch(time),
                                context.tr,
                              ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 12, color: p.textMuted),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  HostConnectButtons(
                    host: host,
                    onAction: widget.onAction,
                    compact: true,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
