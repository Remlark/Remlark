import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:provider/provider.dart';

import '../../../app/theme/app_palette.dart';
import '../../../l10n/app_localizations.dart';
import '../../../ui_kit/buttons.dart';
import '../../../ui_kit/panel.dart';
import '../../../utils/file_drag_out/file_drag_out.dart';
import '../../../utils/shell_utils.dart';
import '../../../utils/ui_utils.dart';
import '../../workspace/workspace_controller.dart';
import '../../workspace/workspace_tab.dart';
import '../file_source.dart';
import '../sftp_service.dart';
import '../sftp_tab.dart';
import '../transfer_manager.dart';
import 'file_pane.dart';
import 'transfer_queue.dart';

/// SFTP 标签视图：左侧本地、右侧远程，中间传输箭头，底部传输队列
class SftpView extends StatefulWidget {
  const SftpView({super.key, required this.tab});

  final SftpTab tab;

  @override
  State<SftpView> createState() => _SftpViewState();
}

class _SftpViewState extends State<SftpView> {
  final _localKey = GlobalKey<FilePaneState>();
  var _remoteKey = GlobalKey<FilePaneState>();
  SftpService? _remoteFor;
  final _local = LocalFileSource();
  TransferManager? _bound;

  SftpTab get t => widget.tab;

  @override
  void dispose() {
    _bound?.removeCompleteListener(_onDone);
    super.dispose();
  }

  /// 绑定传输完成回调：完成后刷新目标栏（重连后传输管理器会更换）
  void _bind() {
    final tm = t.session.transfers;
    if (tm == _bound) return;
    _bound?.removeCompleteListener(_onDone);
    tm?.addCompleteListener(_onDone);
    _bound = tm;
  }

  void _onDone(TransferTask task) {
    if (!mounted) return;
    if (task.direction == TransferDirection.upload) {
      _remoteKey.currentState?.refresh();
    } else {
      _localKey.currentState?.refresh();
    }
  }

  /// 上传本地文件到远程当前目录
  void _upload(List<String> paths) {
    final tm = t.session.transfers;
    final dir = _remoteKey.currentState?.path;
    if (tm == null || dir == null || dir.isEmpty) {
      UiUtils.toast(context.tr('terminal.not_connected'), error: true);
      return;
    }
    for (final p in paths) {
      tm.upload(p, dir);
    }
  }

  /// 下载远程文件到本地当前目录
  void _download(List<FileEntry> files) {
    final tm = t.session.transfers;
    final dir = _localKey.currentState?.path;
    if (tm == null || dir == null || dir.isEmpty) return;
    for (final f in files) {
      tm.download(f, dir);
    }
  }

  /// 远程文件拖到系统文件管理器：放下后经传输队列下载到系统给定的路径
  Future<bool> _dragOut(SftpService sftp, List<FileEntry> files) {
    return FileDragOut.instance.start(
      DragOutSource(
        items: files,
        walk: (dir) async => [
          for (final (path, rel, size) in await sftp.walkRemote(dir))
            (FileEntry(name: p.basename(rel), path: path, isDir: false, isLink: false, size: size), rel),
        ],
        fetch: (entry, localPath) async {
          final tm = t.session.transfers;
          if (tm == null) throw StateError(context.tr('terminal.not_connected'));
          final task = tm.download(entry, p.dirname(localPath), asName: p.basename(localPath));
          if (!await TransferManager.waitAll([task])) throw StateError(task.error ?? task.status.name);
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    _bind();
    final sftp = t.session.sftp;
    // 重连后 SFTP 实例变化：更换远程栏 key 使其重新加载
    if (sftp != _remoteFor) {
      _remoteFor = sftp;
      _remoteKey = GlobalKey<FilePaneState>();
    }
    final connected = t.state == SessionState.connected && sftp != null;
    final collapsed = t.uiState['queueCollapsed'] as bool? ?? false;
    final remoteTitle = '${context.tr('sftp.remote')} · ${t.host.name}';
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  child: FilePane(
                    key: _localKey,
                    source: _local,
                    title: context.tr('sftp.local'),
                    icon: Icons.laptop_mac_outlined,
                    initialPath: t.localPath,
                    onPathChanged: (v) => t.localPath = v,
                    transferLabel: context.tr('sftp.upload'),
                    transferIcon: Icons.upload_rounded,
                    onTransfer: (files) => _upload(files.map((f) => f.path).toList()),
                  ),
                ),
                _Arrows(
                  onUpload: connected
                      ? () => _upload(_localKey.currentState?.selection.map((f) => f.path).toList() ?? [])
                      : null,
                  onDownload: connected ? () => _download(_remoteKey.currentState?.selection ?? []) : null,
                ),
                Expanded(
                  child: connected
                      ? FilePane(
                          key: _remoteKey,
                          source: RemoteFileSource(sftp),
                          title: remoteTitle,
                          icon: Icons.dns_outlined,
                          status: _ConnectedDot(text: context.tr('session.state.connected')),
                          initialPath: t.remotePath,
                          onPathChanged: (v) => t.remotePath = v,
                          transferLabel: context.tr('sftp.download'),
                          transferIcon: Icons.download_rounded,
                          onTransfer: _download,
                          onExternalDrop: _upload,
                          onDragOut: FileDragOut.instance.supported ? (files) => _dragOut(sftp, files) : null,
                          extraMenu: (ctx) => [
                            (
                              ctx.tr('sftp.cd_terminal'),
                              (f) => f.isDir,
                              (f) {
                                t.session.sendRaw('cd ${ShellUtils.quote(f.path)}\r');
                                ctx.read<WorkspaceController>().activate(t.session.id);
                              },
                            ),
                          ],
                        )
                      : AppPanel(
                          padding: EdgeInsets.zero,
                          child: EmptyState(
                            icon: Icons.link_off,
                            title: context.tr(
                              t.state == SessionState.connecting
                                  ? 'session.state.connecting'
                                  : 'terminal.not_connected',
                            ),
                            action: t.state == SessionState.connecting
                                ? null
                                : OutlinedButton.icon(
                                    icon: const Icon(Icons.refresh, size: 16),
                                    label: Text(context.tr('terminal.reconnect')),
                                    onPressed: t.reconnect,
                                  ),
                          ),
                        ),
                ),
              ],
            ),
          ),
          if (t.session.transfers != null) ...[
            const SizedBox(height: 12),
            TransferQueue(
              manager: t.session.transfers!,
              hostName: t.host.name,
              collapsed: collapsed,
              onCollapse: (v) => setState(() => t.uiState['queueCollapsed'] = v),
            ),
          ],
        ],
      ),
    );
  }
}

/// 两栏之间的传输箭头：→ 上传选中的本地文件，← 下载选中的远程文件
class _Arrows extends StatelessWidget {
  const _Arrows({this.onUpload, this.onDownload});

  final VoidCallback? onUpload;
  final VoidCallback? onDownload;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 56,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          ToolButton(icon: Icons.arrow_forward, tooltip: context.tr('sftp.upload_selected'), onPressed: onUpload),
          const SizedBox(height: 12),
          ToolButton(icon: Icons.arrow_back, tooltip: context.tr('sftp.download_selected'), onPressed: onDownload),
        ],
      ),
    );
  }
}

/// 已连接状态点
class _ConnectedDot extends StatelessWidget {
  const _ConnectedDot({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(color: p.success, shape: BoxShape.circle),
        ),
        const SizedBox(width: 6),
        Text(text, style: TextStyle(fontSize: 13, color: p.success)),
      ],
    );
  }
}
