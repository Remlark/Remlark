import 'package:desktop_drop/desktop_drop.dart';
import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';

import '../../../app/theme/app_palette.dart';
import '../../../l10n/app_localizations.dart';
import '../../../ui_kit/buttons.dart';
import '../../../ui_kit/panel.dart';
import '../../../utils/ui_utils.dart';
import '../../sftp/ui/transfer_list.dart';
import '../../workspace/ui/session_status_bar.dart';
import '../../workspace/workspace_tab.dart';
import '../vnc/finder_locator.dart';
import '../vnc/vnc_session.dart';
import 'desktop_status.dart';
import 'remote_screen.dart';

/// VNC 视图：应用内渲染远程画面，支持拖拽上传（经关联 SSH 主机）与剪贴板同步
class VncView extends StatefulWidget {
  const VncView({super.key, required this.session, this.compact = false});

  final VncSession session;

  /// 网格中隐藏工具与状态栏，保留画面及输入。
  final bool compact;

  @override
  State<VncView> createState() => _VncViewState();
}

class _VncViewState extends State<VncView> {
  bool _fit = true;
  bool _dragging = false;
  final _screenKey = GlobalKey<RemoteScreenState>();

  VncSession get s => widget.session;

  @override
  void initState() {
    super.initState();
    s.clipboard.onNotice = _notice;
  }

  @override
  void didUpdateWidget(covariant VncView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.session != widget.session) {
      oldWidget.session.clipboard.onNotice = null;
      s.clipboard.onNotice = _notice;
    }
  }

  @override
  void dispose() {
    if (s.clipboard.onNotice == _notice) s.clipboard.onNotice = null;
    super.dispose();
  }

  /// 剪贴板桥的提示（开始粘贴、已拉取文件、失败原因）
  void _notice(String key, Map<String, Object> args, {bool error = false}) {
    final ctx = UiUtils.context;
    if (ctx == null) return;
    UiUtils.toast(S.of(ctx).t(key, args), error: error);
  }

  /// 上传文件；[dropGlobal] 为拖放松手的全局坐标，用于确定远程目标文件夹
  Future<void> _upload(List<String> paths, {Offset? dropGlobal}) async {
    if (paths.isEmpty) return;
    if (!s.hasSsh) {
      UiUtils.toast(context.tr('vnc.no_transfer_host'), error: true);
      return;
    }
    final remote = dropGlobal == null ? null : _screenKey.currentState?.remoteFromGlobal(dropGlobal);
    final tr = S.of(context);
    try {
      final dir = await s.uploadFiles(paths, remotePoint: remote);
      UiUtils.toast(tr.t('vnc.uploading_to', {'count': paths.length, 'dir': dir}));
    } on FinderLocateException catch (e) {
      UiUtils.toast(tr.t(e.code, {'detail': e.detail ?? ''}), error: true);
    } catch (e) {
      UiUtils.toast('$e', error: true);
    }
  }

  /// 拖动经过画面时同步移动远程鼠标，便于看清将放到哪个窗口
  void _dragMove(Offset global) {
    final p = _screenKey.currentState?.remoteFromGlobal(global);
    if (p != null) s.pointerEvent(p.dx.round(), p.dy.round(), 0);
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: s,
      builder: (context, _) => Column(
        children: [
          if (!widget.compact) _toolbar(context),
          if (!widget.compact) const Divider(height: 1),
          // 远程已锁屏：画面可能仍是锁屏前的桌面，但输入由锁屏界面接收，点击无效
          if (!widget.compact && s.state == SessionState.connected && s.remoteLocked == true)
            WarningBar(
              icon: Icons.lock_outline,
              text: context.tr(s.canUnlock ? 'vnc.locked' : 'vnc.locked.manual'),
              action: s.canUnlock
                  ? FilledButton.icon(
                      icon: const Icon(Icons.lock_open, size: 16),
                      label: Text(context.tr('vnc.unlock')),
                      onPressed: () async {
                        final tr = S.of(context);
                        final ok = await s.unlock();
                        if (!ok) {
                          UiUtils.toast(tr.t('vnc.unlock.failed'), error: true);
                        }
                      },
                    )
                  : null,
            ),
          Expanded(
            key: const ValueKey('desktop-content'),
            child: s.state != SessionState.connected
                ? DesktopStatus(tab: s)
                : DropTarget(
                    onDragEntered: (_) {
                      setState(() => _dragging = true);
                      // 提前建立传输连接，松手后只需查询位置
                      if (s.hasSsh) s.prepareTransfer().ignore();
                    },
                    onDragUpdated: (d) => _dragMove(d.globalPosition),
                    onDragExited: (_) => setState(() => _dragging = false),
                    onDragDone: (d) {
                      setState(() => _dragging = false);
                      _upload(d.files.map((f) => f.path).toList(), dropGlobal: d.globalPosition);
                    },
                    child: Stack(
                      children: [
                        Positioned.fill(
                          child: RemoteScreen(key: _screenKey, display: s, fit: widget.compact || _fit),
                        ),
                        if (_dragging) DropHint(text: context.tr('vnc.drop_hint')),
                        if (!widget.compact && s.transfers != null)
                          Positioned(
                            right: 12,
                            bottom: 12,
                            width: 340,
                            // 没有任务时整个浮层（含边框与阴影）都不显示
                            child: ListenableBuilder(
                              listenable: s.transfers!,
                              builder: (context, _) => s.transfers!.tasks.isEmpty
                                  ? const SizedBox.shrink()
                                  : Material(
                                      elevation: 6,
                                      color: context.palette.panelRaised,
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(12),
                                        side: BorderSide(color: context.palette.borderStrong),
                                      ),
                                      clipBehavior: Clip.antiAlias,
                                      child: TransferList(manager: s.transfers!, maxHeight: 160),
                                    ),
                            ),
                          ),
                      ],
                    ),
                  ),
          ),
          if (!widget.compact)
            SessionStatusBar(
              tab: s,
              detail: s.client == null ? null : '${s.client!.desktopName}  ${s.client!.width} × ${s.client!.height}',
            ),
        ],
      ),
    );
  }

  Widget _toolbar(BuildContext context) {
    final c = s.client;
    return Container(
      height: 48,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Row(
        children: [
          ToolButton(
            compact: true,
            icon: _fit ? Icons.fit_screen_outlined : Icons.crop_free,
            label: context.tr(_fit ? 'vnc.fit' : 'vnc.actual_size'),
            tooltip: context.tr(_fit ? 'vnc.actual_size' : 'vnc.fit'),
            onPressed: () => setState(() => _fit = !_fit),
          ),
          const SizedBox(width: 8),
          ToolButton(
            compact: true,
            icon: Icons.keyboard_outlined,
            label: 'Ctrl + Alt + Del',
            onPressed: c == null ? null : s.sendCtrlAltDel,
          ),
          Container(
            width: 1,
            height: 20,
            margin: const EdgeInsets.symmetric(horizontal: 10),
            color: context.palette.border,
          ),
          ToolButton(
            compact: true,
            icon: s.clipboardSync ? Icons.content_paste : Icons.content_paste_off,
            label: context.tr('vnc.clipboard_sync'),
            selected: s.clipboardSync,
            onPressed: () => s.setClipboardSync(!s.clipboardSync),
          ),
          const SizedBox(width: 8),
          ToolButton(
            compact: true,
            icon: Icons.upload_file_outlined,
            label: context.tr('vnc.upload'),
            onPressed: () async {
              final files = await openFiles();
              await _upload(files.map((f) => f.path).toList());
            },
          ),
          const SizedBox(width: 8),
          ToolButton(
            compact: true,
            icon: Icons.refresh,
            label: context.tr('terminal.reconnect'),
            onPressed: s.reconnect,
          ),
        ],
      ),
    );
  }
}
