import 'package:desktop_drop/desktop_drop.dart';
import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';

import '../../../l10n/app_localizations.dart';
import '../../../utils/ui_utils.dart';
import '../../sftp/ui/transfer_list.dart';
import '../../workspace/workspace_tab.dart';
import '../vnc/vnc_session.dart';
import 'desktop_status.dart';
import 'remote_screen.dart';

/// VNC 视图：应用内渲染远程画面，支持拖拽上传（经关联 SSH 主机）与剪贴板同步
class VncView extends StatefulWidget {
  const VncView({super.key, required this.session});

  final VncSession session;

  @override
  State<VncView> createState() => _VncViewState();
}

class _VncViewState extends State<VncView> {
  bool _fit = true;
  bool _dragging = false;

  VncSession get s => widget.session;

  Future<void> _upload(List<String> paths) async {
    if (paths.isEmpty) return;
    if (s.transferHostUuid == null) {
      UiUtils.toast(context.tr('vnc.no_transfer_host'), error: true);
      return;
    }
    try {
      await s.uploadFiles(paths);
      UiUtils.toast(S.of(UiUtils.context!).t('upload.queued', {'count': paths.length}));
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
          _toolbar(context),
          const Divider(height: 1),
          Expanded(
            child: s.state != SessionState.connected
                ? DesktopStatus(tab: s)
                : DropTarget(
                    onDragEntered: (_) => setState(() => _dragging = true),
                    onDragExited: (_) => setState(() => _dragging = false),
                    onDragDone: (d) {
                      setState(() => _dragging = false);
                      _upload(d.files.map((f) => f.path).toList());
                    },
                    child: Stack(
                      children: [
                        Positioned.fill(
                          child: RemoteScreen(display: s, fit: _fit),
                        ),
                        if (_dragging) DropHint(text: context.tr('vnc.drop_hint', {'dir': s.transferDir})),
                        if (s.transfers != null)
                          Positioned(
                            right: 12,
                            bottom: 12,
                            width: 340,
                            child: Material(
                              elevation: 4,
                              borderRadius: BorderRadius.circular(8),
                              child: TransferList(manager: s.transfers!, maxHeight: 160),
                            ),
                          ),
                      ],
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _toolbar(BuildContext context) {
    final c = s.client;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: Row(
        children: [
          Expanded(
            child: Text(
              c == null ? s.host.endpoint : '${c.desktopName}  ${c.width}×${c.height}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.labelMedium,
            ),
          ),
          TextButton.icon(
            icon: const Icon(Icons.keyboard, size: 16),
            label: const Text('Ctrl+Alt+Del'),
            onPressed: c == null ? null : s.sendCtrlAltDel,
          ),
          IconButton(
            tooltip: context.tr(_fit ? 'vnc.actual_size' : 'vnc.fit'),
            icon: Icon(_fit ? Icons.fit_screen : Icons.crop_free, size: 18),
            onPressed: () => setState(() => _fit = !_fit),
          ),
          IconButton(
            tooltip: context.tr('vnc.clipboard_sync'),
            isSelected: s.clipboardSync,
            icon: const Icon(Icons.content_paste_off, size: 18),
            selectedIcon: const Icon(Icons.content_paste, size: 18),
            onPressed: () => setState(() => s.clipboardSync = !s.clipboardSync),
          ),
          IconButton(
            tooltip: context.tr('vnc.upload'),
            icon: const Icon(Icons.upload_file, size: 18),
            onPressed: () async {
              final files = await openFiles();
              await _upload(files.map((f) => f.path).toList());
            },
          ),
          IconButton(
            tooltip: context.tr('terminal.reconnect'),
            icon: const Icon(Icons.refresh, size: 18),
            onPressed: s.reconnect,
          ),
        ],
      ),
    );
  }
}
