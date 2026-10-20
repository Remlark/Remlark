import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../app/theme/app_palette.dart';
import '../../../l10n/app_localizations.dart';
import '../../../ui_kit/buttons.dart';
import '../../hosts/ui/os_icon.dart';
import '../../hosts/ui/protocol_tag.dart';
import '../../remote_desktop/rdp/rdp_session.dart';
import '../../remote_desktop/ui/rdp_view.dart';
import '../../remote_desktop/ui/vnc_view.dart';
import '../../remote_desktop/vnc/vnc_session.dart';
import '../../sftp/sftp_tab.dart';
import '../../sftp/ui/sftp_view.dart';
import '../../terminal/terminal_session.dart';
import '../../terminal/ui/terminal_tab_view.dart';
import '../workspace_controller.dart';
import '../workspace_tab.dart';

/// 单窗口与混合协议网格共用同一棵会话树，切换时不重建连接或重复挂载屏幕。
class SessionCanvas extends StatelessWidget {
  const SessionCanvas({super.key});

  /// 按会话数量计算近似正方形的列数。
  static int columnsFor(int count) => count <= 1 ? 1 : math.sqrt(count).ceil();

  /// 固定会话子树身份，仅修改位置、尺寸及可见性。
  @override
  Widget build(BuildContext context) {
    final w = context.watch<WorkspaceController>();
    return LayoutBuilder(
      builder: (context, box) {
        final grid = w.showingGrid;
        final ids = w.gridSessions.map((t) => t.id).toList();
        final cols = columnsFor(ids.length);
        final rows = math.max(1, (ids.length / cols).ceil());
        const inset = 10.0;
        const gap = 8.0;
        final cellWidth = math.max(
          0.0,
          (box.maxWidth - inset * 2 - gap * (cols - 1)) / cols,
        );
        final cellHeight = math.max(
          0.0,
          (box.maxHeight - inset * 2 - gap * (rows - 1)) / rows,
        );
        return Stack(
          children: [
            for (final tab in w.tabs)
              Positioned(
                key: ValueKey('session-${tab.id}'),
                left: grid && ids.contains(tab.id)
                    ? inset + ids.indexOf(tab.id) % cols * (cellWidth + gap)
                    : 0,
                top: grid && ids.contains(tab.id)
                    ? inset + ids.indexOf(tab.id) ~/ cols * (cellHeight + gap)
                    : 0,
                width: grid && ids.contains(tab.id) ? cellWidth : box.maxWidth,
                height: grid && ids.contains(tab.id)
                    ? cellHeight
                    : box.maxHeight,
                child: _SessionVisibility(
                  visible: grid ? ids.contains(tab.id) : w.active == tab,
                  child: _SessionTile(
                    tab: tab,
                    grid: grid && ids.contains(tab.id),
                    active: w.active == tab,
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}

/// 隐藏会话保留视图状态，但不得获取键盘焦点或驱动动画。
/// 使用 Visibility（等价于 Offstage + TickerMode + ExcludeFocus），子组件可通过 Visibility.of 判断是否可见，
/// 例如文件拖放只由可见的会话接收（见 FileDropTarget）
class _SessionVisibility extends StatelessWidget {
  const _SessionVisibility({required this.visible, required this.child});
  final bool visible;
  final Widget child;

  @override
  Widget build(BuildContext context) => Visibility(visible: visible, maintainState: true, child: child);
}

/// 网格标题栏独立响应聚焦手势，不截获终端选词或远程桌面的双击。
class _SessionTile extends StatelessWidget {
  const _SessionTile({
    required this.tab,
    required this.grid,
    required this.active,
  });
  final WorkspaceTab tab;
  final bool grid;
  final bool active;

  /// 标题、广播标记及聚焦操作；单窗口隐藏标题而保留内容身份。
  @override
  Widget build(BuildContext context) {
    final w = context.read<WorkspaceController>();
    final p = context.palette;
    final broadcasting = w.broadcast && w.broadcastIds.contains(tab.id);
    return Listener(
      onPointerDown: (_) => w.activate(tab.id),
      child: Container(
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          color: p.panel,
          borderRadius: BorderRadius.circular(grid ? 8 : 0),
        ),
        foregroundDecoration: grid
            ? BoxDecoration(
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: active ? p.accent : p.border,
                  width: active ? 1.5 : 1,
                ),
              )
            : const BoxDecoration(),
        child: Column(
          children: [
            if (grid)
              GestureDetector(
                key: ValueKey('grid-header-${tab.id}'),
                behavior: HitTestBehavior.opaque,
                onDoubleTap: w.broadcast
                    ? null
                    : () => w.focusGridSession(tab.id),
                child: Container(
                  height: 38,
                  padding: const EdgeInsets.only(left: 10, right: 4),
                  decoration: BoxDecoration(
                    border: Border(bottom: BorderSide(color: p.border)),
                  ),
                  child: Row(
                    children: [
                      if (broadcasting)
                        Tooltip(
                          message: context.tr('workspace.broadcast.target'),
                          child: Icon(
                            Icons.podcasts_rounded,
                            size: 18,
                            color: p.warning,
                          ),
                        )
                      else
                        OsIcon(host: tab.host, size: 20),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          tab.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: p.text,
                          ),
                        ),
                      ),
                      const SizedBox(width: 6),
                      ProtocolTag(tab.kindLabel, small: true),
                      const SizedBox(width: 4),
                      GhostIconButton(
                        icon: Icons.open_in_full_rounded,
                        size: 28,
                        tooltip: context.tr(
                          w.broadcast
                              ? 'workspace.layout.locked'
                              : 'workspace.grid.focus',
                        ),
                        onPressed: w.broadcast
                            ? null
                            : () => w.focusGridSession(tab.id),
                      ),
                    ],
                  ),
                ),
              ),
            Expanded(
              key: ValueKey('body-${tab.id}'),
              child: RepaintBoundary(
                child: _SessionBody(tab: tab, compact: grid, active: active),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 按真实会话类型渲染，紧凑模式仅收起工具栏，不改变协议行为。
class _SessionBody extends StatelessWidget {
  const _SessionBody({
    required this.tab,
    required this.compact,
    required this.active,
  });
  final WorkspaceTab tab;
  final bool compact;
  final bool active;

  @override
  Widget build(BuildContext context) => switch (tab) {
    TerminalSession t => TerminalTabView(
      session: t,
      compact: compact,
      autofocus: active,
    ),
    VncSession t => VncView(session: t, compact: compact),
    RdpSession t => RdpView(session: t, compact: compact),
    SftpTab t => ListenableBuilder(
      listenable: t,
      builder: (_, _) => SftpView(tab: t),
    ),
    _ => const SizedBox.shrink(),
  };
}
