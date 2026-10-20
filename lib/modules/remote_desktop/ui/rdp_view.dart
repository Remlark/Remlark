import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';

import '../../../ui_kit/file_drop_target.dart';
import '../../../app/theme/app_palette.dart';
import '../../../l10n/app_localizations.dart';
import '../../../ui_kit/buttons.dart';
import '../../../utils/ui_utils.dart';
import '../../workspace/ui/session_status_bar.dart';
import '../../workspace/workspace_tab.dart';
import '../rdp/rdp_session.dart';
import 'desktop_status.dart';
import 'remote_screen.dart';

/// RDP 视图：应用内渲染远程桌面，工具栏提供特殊按键、共享文件夹与重新连接；
/// 拖入的文件放入共享文件夹并写入远程剪贴板，可在远程直接粘贴
class RdpView extends StatefulWidget {
  const RdpView({super.key, required this.session, this.compact = false});

  final RdpSession session;

  /// 网格中隐藏工具与状态栏，保留画面及输入。
  final bool compact;

  @override
  State<RdpView> createState() => _RdpViewState();
}

class _RdpViewState extends State<RdpView> {
  bool _dragging = false;

  /// 远程画面，用于把拖放位置换算为远程坐标
  final _screenKey = GlobalKey<RemoteScreenState>();

  RdpSession get s => widget.session;

  @override
  void initState() {
    super.initState();
    s.onNotice = _onNotice;
  }

  @override
  void dispose() {
    if (s.onNotice == _onNotice) s.onNotice = null;
    super.dispose();
  }

  void _onNotice(RdpNotice notice, int count) {
    final t = S.of(UiUtils.context!);
    switch (notice) {
      case RdpNotice.filesTooLarge:
        UiUtils.toast(t.t('rdp.files_too_large', {'mb': count}), error: true);
    }
  }

  /// 发送文件；[dropGlobal] 为拖放松手的全局坐标，用于粘贴到松手处的文件夹
  Future<void> _drop(List<String> paths, {Offset? dropGlobal}) async {
    if (paths.isEmpty) return;
    final p = dropGlobal == null ? null : _screenKey.currentState?.remoteFromGlobal(dropGlobal);
    try {
      await s.dropFiles(paths, at: p == null ? null : (p.dx.round(), p.dy.round()));
    } catch (e) {
      UiUtils.toast('$e', error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: s,
      builder: (context, _) => Column(
        children: [
          if (!widget.compact) _toolbar(context),
          if (!widget.compact) const Divider(height: 1),
          Expanded(
            key: const ValueKey('desktop-content'),
            child: s.state != SessionState.connected
                ? DesktopStatus(tab: s)
                : FileDropTarget(
                    onDragEntered: (_) => setState(() => _dragging = true),
                    // 拖动经过时同步移动远程鼠标，便于看清将放到哪个窗口
                    onDragUpdated: (d) {
                      final p = _screenKey.currentState?.remoteFromGlobal(d.globalPosition);
                      if (p != null) s.pointerEvent(p.dx.round(), p.dy.round(), 0);
                    },
                    onDragExited: (_) => setState(() => _dragging = false),
                    onDragDone: (d) {
                      setState(() => _dragging = false);
                      _drop(d.files.map((f) => f.path).toList(), dropGlobal: d.globalPosition);
                    },
                    child: Stack(
                      children: [
                        Positioned.fill(
                          child: RemoteScreen(key: _screenKey, display: s),
                        ),
                        if (_dragging) DropHint(text: context.tr('rdp.drop_hint')),
                      ],
                    ),
                  ),
          ),
          if (!widget.compact)
            SessionStatusBar(
              tab: s,
              detail: s.state == SessionState.connected ? '${s.frameWidth} × ${s.frameHeight}' : null,
              trailing: [
                // 远程复制的文件正在下载到本地
                if (s.filesTotalKb > 0) ...[
                  Text(
                    context.tr('rdp.files_downloading'),
                    style: TextStyle(fontSize: 12.5, color: context.palette.textMuted),
                  ),
                  const SizedBox(width: 8),
                  SizedBox(
                    width: 120,
                    child: LinearProgressIndicator(value: s.filesDoneKb / s.filesTotalKb, minHeight: 4),
                  ),
                ],
              ],
            ),
        ],
      ),
    );
  }

  Widget _toolbar(BuildContext context) {
    final connected = s.state == SessionState.connected;
    return Container(
      height: 48,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Row(
        children: [
          ToolButton(
            compact: true,
            icon: Icons.keyboard_outlined,
            label: 'Ctrl + Alt + Del',
            onPressed: connected ? s.sendCtrlAltDel : null,
          ),
          const SizedBox(width: 8),
          ToolButton(
            compact: true,
            icon: Icons.window,
            label: context.tr('rdp.win_key'),
            onPressed: connected ? s.sendWinKey : null,
          ),
          Container(
            width: 1,
            height: 20,
            margin: const EdgeInsets.symmetric(horizontal: 10),
            color: context.palette.border,
          ),
          ToolButton(
            compact: true,
            icon: Icons.upload_file_outlined,
            label: context.tr('rdp.send_files'),
            onPressed: connected
                ? () async {
                    final files = await openFiles();
                    await _drop(files.map((f) => f.path).toList());
                  }
                : null,
          ),
          const SizedBox(width: 8),
          ToolButton(
            compact: true,
            icon: Icons.folder_open_outlined,
            label: context.tr('rdp.open_folder'),
            onPressed: s.openSharedDir,
          ),
          const SizedBox(width: 8),
          ToolButton(
            compact: true,
            icon: Icons.refresh,
            label: context.tr('terminal.reconnect'),
            onPressed: s.state == SessionState.connecting ? null : s.reconnect,
          ),
        ],
      ),
    );
  }
}
