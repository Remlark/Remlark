import 'package:desktop_drop/desktop_drop.dart';
import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../l10n/app_localizations.dart';
import '../../../utils/format_utils.dart';
import '../../../utils/shell_utils.dart';
import '../../../utils/ui_utils.dart';
import '../../terminal/terminal_session.dart';
import '../sftp_service.dart';
import '../transfer_manager.dart';
import 'transfer_list.dart';

/// SFTP 面板：浏览远程目录、上传、下载、新建目录、重命名、删除，底部显示传输进度
class SftpPanel extends StatefulWidget {
  const SftpPanel({super.key, required this.session});

  final TerminalSession session;

  @override
  State<SftpPanel> createState() => _SftpPanelState();
}

class _SftpPanelState extends State<SftpPanel> {
  final _pathCtrl = TextEditingController();
  List<RemoteFile> _files = [];
  String _path = '';
  bool _loading = false;
  String? _error;
  String? _selected;
  bool _dragging = false;
  TransferManager? _boundTransfers;

  SftpService? get _sftp => widget.session.sftp;

  @override
  void initState() {
    super.initState();
    _init();
  }

  @override
  void dispose() {
    _boundTransfers?.removeCompleteListener(_onTransferDone);
    _pathCtrl.dispose();
    super.dispose();
  }

  /// 上传完成后刷新当前目录
  void _onTransferDone(TransferTask t) {
    if (t.direction == TransferDirection.upload && mounted) _list(_path, quiet: true);
  }

  void _bindTransfers() {
    final tm = widget.session.transfers;
    if (tm == _boundTransfers) return;
    _boundTransfers?.removeCompleteListener(_onTransferDone);
    tm?.addCompleteListener(_onTransferDone);
    _boundTransfers = tm;
  }

  Future<void> _init() async {
    final sftp = _sftp;
    if (sftp == null) return;
    _bindTransfers();
    try {
      final start = widget.session.lastRemoteDir ?? await sftp.home();
      await _list(start);
    } catch (e) {
      setState(() => _error = '$e');
    }
  }

  Future<void> _list(String path, {bool quiet = false}) async {
    final sftp = _sftp;
    if (sftp == null) return;
    if (!quiet) setState(() => _loading = true);
    try {
      final files = await sftp.list(path);
      if (!mounted) return;
      setState(() {
        _files = files;
        _path = path;
        _pathCtrl.text = path;
        _error = null;
        _loading = false;
        _selected = null;
      });
      widget.session.lastRemoteDir = path;
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = '$e';
          _loading = false;
        });
      }
    }
  }

  Future<void> _mkdir() async {
    final name = await UiUtils.prompt(context, title: context.tr('sftp.mkdir'), label: context.tr('sftp.name'));
    if (name == null || name.trim().isEmpty) return;
    await _run(() => _sftp!.mkdir(ShellUtils.joinRemote(_path, name.trim())));
  }

  Future<void> _rename(RemoteFile f) async {
    final name = await UiUtils.prompt(context, title: context.tr('common.rename'), initial: f.name);
    if (name == null || name.trim().isEmpty || name == f.name) return;
    await _run(() => _sftp!.rename(f.path, ShellUtils.joinRemote(_path, name.trim())));
  }

  Future<void> _delete(RemoteFile f) async {
    final ok = await UiUtils.confirm(
      context,
      title: context.tr('sftp.delete'),
      message: context.tr('sftp.delete.message', {'name': f.name}),
      danger: true,
    );
    if (!ok) return;
    await _run(() => _sftp!.delete(f.path, isDir: f.isDir && !f.isLink));
  }

  Future<void> _download(RemoteFile f) async {
    final dir = await getDirectoryPath(confirmButtonText: context.tr('sftp.download'));
    if (dir == null) return;
    widget.session.transfers?.download(f, dir);
  }

  Future<void> _uploadPicked() async {
    final files = await openFiles();
    if (files.isEmpty) return;
    for (final f in files) {
      widget.session.transfers?.upload(f.path, _path);
    }
  }

  /// 执行操作并刷新，失败时提示
  Future<void> _run(Future<void> Function() op) async {
    try {
      await op();
    } catch (e) {
      UiUtils.toast('$e', error: true);
    }
    await _list(_path, quiet: true);
  }

  Future<void> _menu(RemoteFile f, Offset pos) async {
    setState(() => _selected = f.path);
    final r = await showMenu<String>(
      context: context,
      position: RelativeRect.fromLTRB(pos.dx, pos.dy, pos.dx + 1, pos.dy + 1),
      items: [
        if (f.isDir) PopupMenuItem(value: 'open', child: Text(context.tr('sftp.open'))),
        PopupMenuItem(value: 'download', child: Text(context.tr('sftp.download'))),
        PopupMenuItem(value: 'rename', child: Text(context.tr('common.rename'))),
        PopupMenuItem(value: 'copy', child: Text(context.tr('sftp.copy_path'))),
        if (f.isDir) PopupMenuItem(value: 'cd', child: Text(context.tr('sftp.cd_terminal'))),
        PopupMenuItem(
          value: 'delete',
          child: Text(context.tr('common.delete'), style: const TextStyle(color: Colors.red)),
        ),
      ],
    );
    switch (r) {
      case 'open':
        _list(f.path);
      case 'download':
        _download(f);
      case 'rename':
        _rename(f);
      case 'copy':
        Clipboard.setData(ClipboardData(text: f.path));
      case 'cd':
        widget.session.sendRaw('cd ${ShellUtils.quote(f.path)}\r');
      case 'delete':
        _delete(f);
    }
  }

  @override
  Widget build(BuildContext context) {
    _bindTransfers();
    final theme = Theme.of(context);
    if (_sftp == null) return Center(child: Text(context.tr('terminal.not_connected')));
    final selected = _files.where((f) => f.path == _selected).firstOrNull;
    return DropTarget(
      onDragEntered: (_) => setState(() => _dragging = true),
      onDragExited: (_) => setState(() => _dragging = false),
      onDragDone: (d) {
        setState(() => _dragging = false);
        for (final f in d.files) {
          widget.session.transfers?.upload(f.path, _path);
        }
      },
      child: Material(
        color: _dragging ? theme.colorScheme.primaryContainer.withValues(alpha: 0.3) : Colors.transparent,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(6, 6, 6, 4),
              child: Row(
                children: [
                  IconButton(
                    tooltip: context.tr('sftp.up'),
                    icon: const Icon(Icons.arrow_upward, size: 18),
                    onPressed: () => _list(ShellUtils.parentRemote(_path)),
                  ),
                  Expanded(
                    child: TextField(
                      controller: _pathCtrl,
                      style: const TextStyle(fontSize: 12, fontFamily: 'monospace'),
                      decoration: const InputDecoration(
                        contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                      ),
                      onSubmitted: (v) => _list(v.trim()),
                    ),
                  ),
                  IconButton(
                    tooltip: context.tr('common.refresh'),
                    icon: const Icon(Icons.refresh, size: 18),
                    onPressed: () => _list(_path),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6),
              child: Row(
                children: [
                  TextButton.icon(
                    icon: const Icon(Icons.upload, size: 16),
                    label: Text(context.tr('sftp.upload')),
                    onPressed: _uploadPicked,
                  ),
                  TextButton.icon(
                    icon: const Icon(Icons.download, size: 16),
                    label: Text(context.tr('sftp.download')),
                    onPressed: selected == null ? null : () => _download(selected),
                  ),
                  IconButton(
                    tooltip: context.tr('sftp.mkdir'),
                    icon: const Icon(Icons.create_new_folder_outlined, size: 18),
                    onPressed: _mkdir,
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : _error != null
                  ? Center(
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Text(_error!, style: const TextStyle(color: Colors.red)),
                      ),
                    )
                  : ListView.builder(
                      itemCount: _files.length,
                      itemExtent: 40,
                      itemBuilder: (context, i) {
                        final f = _files[i];
                        final sel = f.path == _selected;
                        return GestureDetector(
                          onSecondaryTapUp: (d) => _menu(f, d.globalPosition),
                          onDoubleTap: () => f.isDir ? _list(f.path) : _download(f),
                          child: ListTile(
                            dense: true,
                            selected: sel,
                            selectedTileColor: theme.colorScheme.primaryContainer.withValues(alpha: 0.5),
                            visualDensity: VisualDensity.compact,
                            leading: Icon(
                              f.isDir ? Icons.folder : (f.isLink ? Icons.link : Icons.insert_drive_file_outlined),
                              size: 18,
                              color: f.isDir ? Colors.amber.shade700 : null,
                            ),
                            title: Text(
                              f.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(fontSize: 13),
                            ),
                            trailing: Text(
                              f.isDir ? FormatUtils.unixTime(f.modified) : FormatUtils.bytes(f.size),
                              style: theme.textTheme.labelSmall,
                            ),
                            onTap: () => setState(() => _selected = f.path),
                          ),
                        );
                      },
                    ),
            ),
            if (widget.session.transfers != null) TransferList(manager: widget.session.transfers!),
          ],
        ),
      ),
    );
  }
}
