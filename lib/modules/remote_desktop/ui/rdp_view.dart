import 'package:desktop_drop/desktop_drop.dart';
import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';

import '../../../l10n/app_localizations.dart';
import '../../../utils/ui_utils.dart';
import '../../workspace/workspace_tab.dart';
import '../rdp/rdp_session.dart';
import 'desktop_status.dart';
import 'remote_screen.dart';

/// RDP 视图：应用内渲染远程桌面，工具栏提供特殊按键、共享文件夹与重新连接；
/// 拖入的文件放入共享文件夹并写入远程剪贴板，可在远程直接粘贴
class RdpView extends StatefulWidget {
  const RdpView({super.key, required this.session});

  final RdpSession session;

  @override
  State<RdpView> createState() => _RdpViewState();
}

class _RdpViewState extends State<RdpView> {
  bool _dragging = false;

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
      case RdpNotice.filesFromRemote:
        UiUtils.toast(t.t('rdp.files_from_remote', {'count': count}));
      case RdpNotice.filesTooLarge:
        UiUtils.toast(t.t('rdp.files_too_large', {'mb': count}), error: true);
      case RdpNotice.filesShared:
        UiUtils.toast(t.t('rdp.files_shared', {'count': count}));
    }
  }

  Future<void> _drop(List<String> paths) async {
    if (paths.isEmpty) return;
    try {
      await s.dropFiles(paths);
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
                      _drop(d.files.map((f) => f.path).toList());
                    },
                    child: Stack(
                      children: [
                        Positioned.fill(child: RemoteScreen(display: s)),
                        if (_dragging) DropHint(text: context.tr('rdp.drop_hint')),
                        if (s.filesTotalKb > 0)
                          Positioned(
                            right: 12,
                            bottom: 12,
                            width: 280,
                            child: Card(
                              child: Padding(
                                padding: const EdgeInsets.all(10),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      context.tr('rdp.files_downloading'),
                                      style: Theme.of(context).textTheme.labelMedium,
                                    ),
                                    const SizedBox(height: 6),
                                    LinearProgressIndicator(value: s.filesDoneKb / s.filesTotalKb),
                                  ],
                                ),
                              ),
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
    final connected = s.state == SessionState.connected;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: Row(
        children: [
          Text(
            '${s.host.endpoint}${connected ? '  ${s.frameWidth}×${s.frameHeight}' : ''}',
            style: Theme.of(context).textTheme.labelMedium,
          ),
          const Spacer(),
          TextButton.icon(
            icon: const Icon(Icons.keyboard, size: 16),
            label: const Text('Ctrl+Alt+Del'),
            onPressed: connected ? s.sendCtrlAltDel : null,
          ),
          IconButton(
            tooltip: context.tr('rdp.win_key'),
            icon: const Icon(Icons.window, size: 18),
            onPressed: connected ? s.sendWinKey : null,
          ),
          IconButton(
            tooltip: context.tr('rdp.send_files'),
            icon: const Icon(Icons.upload_file, size: 18),
            onPressed: connected
                ? () async {
                    final files = await openFiles();
                    await _drop(files.map((f) => f.path).toList());
                  }
                : null,
          ),
          IconButton(
            tooltip: context.tr('rdp.open_folder'),
            icon: const Icon(Icons.folder_open, size: 18),
            onPressed: s.openSharedDir,
          ),
          IconButton(
            tooltip: context.tr('terminal.reconnect'),
            icon: const Icon(Icons.refresh, size: 18),
            onPressed: s.state == SessionState.connecting ? null : s.reconnect,
          ),
        ],
      ),
    );
  }
}
