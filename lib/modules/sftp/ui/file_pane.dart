import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../ui_kit/file_drop_target.dart';
import '../../../app/theme/app_palette.dart';
import '../../../app/theme/app_theme.dart';
import '../../../l10n/app_localizations.dart';
import '../../../ui_kit/app_table.dart';
import '../../../ui_kit/buttons.dart';
import '../../../utils/format_utils.dart';
import '../../../utils/ui_utils.dart';
import '../file_source.dart';
import '../sftp_service.dart';
import '../../../ui_kit/app_menu.dart';

/// 栏间拖动的数据：来源栏是否远程 + 拖动的文件
class FilePaneDrag {
  const FilePaneDrag({required this.fromRemote, required this.files});

  final bool fromRemote;
  final List<FileEntry> files;
}

/// 排序字段
enum _SortBy { name, size, modified }

/// 文件栏：标题与操作、导航（后退 / 前进 / 上级 / 刷新 / 路径）、文件表格。
/// 本地栏与远程栏共用，通过 [FileSource] 区分文件系统。
/// 只接受来自另一栏的拖放（同栏拖动不会触发传输）；远程栏还接受系统文件拖入上传
class FilePane extends StatefulWidget {
  const FilePane({
    super.key,
    required this.source,
    required this.title,
    required this.icon,
    required this.transferLabel,
    required this.transferIcon,
    required this.onTransfer,
    required this.onPathChanged,
    this.initialPath,
    this.status,
    this.onExternalDrop,
    this.extraMenu,
  });

  final FileSource source;
  final String title;
  final IconData icon;

  /// 标题后的状态（远程栏显示连接状态）
  final Widget? status;

  /// 传输按钮文字与图标（本地栏为“上传”，远程栏为“下载”）
  final String transferLabel;
  final IconData transferIcon;

  /// 把文件传到另一栏的当前目录
  final void Function(List<FileEntry> files) onTransfer;

  /// 目录变化
  final ValueChanged<String> onPathChanged;
  final String? initialPath;

  /// 系统文件拖入（仅远程栏）
  final void Function(List<String> paths)? onExternalDrop;

  /// 额外的右键菜单项（如远程目录“在终端中进入”）：(文本, 是否可用, 执行)
  final List<(String, bool Function(FileEntry), void Function(FileEntry))> Function(BuildContext)? extraMenu;

  @override
  State<FilePane> createState() => FilePaneState();
}

class FilePaneState extends State<FilePane> {
  final _pathCtrl = TextEditingController();
  final List<String> _back = [];
  final List<String> _forward = [];
  List<FileEntry> _files = [];
  String _path = '';
  bool _loading = true;
  String? _error;
  final Set<String> _selected = {};
  int? _anchor;
  _SortBy _sortBy = _SortBy.name;
  bool _asc = true;
  bool _dropHover = false;

  FileSource get _src => widget.source;

  /// 当前目录
  String get path => _path;

  /// 当前选中的文件
  List<FileEntry> get selection => _files.where((f) => _selected.contains(f.path)).toList();

  @override
  void initState() {
    super.initState();
    _init();
  }

  @override
  void dispose() {
    _pathCtrl.dispose();
    super.dispose();
  }

  Future<void> _init() async {
    try {
      final start = widget.initialPath ?? await _src.home();
      await _open(start, record: false);
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = '$e';
          _loading = false;
        });
      }
    }
  }

  /// 刷新当前目录（传输完成后由外部调用）
  Future<void> refresh() => _open(_path, record: false, quiet: true);

  /// 打开目录；[record] 为 true 时记入后退历史
  Future<void> _open(String path, {bool record = true, bool quiet = false}) async {
    if (!quiet) setState(() => _loading = true);
    try {
      final files = await _src.list(path);
      if (!mounted) return;
      setState(() {
        if (record && _path.isNotEmpty && _path != path) {
          _back.add(_path);
          _forward.clear();
        }
        _files = files;
        _path = path;
        _pathCtrl.text = path;
        _error = null;
        _loading = false;
        _selected.retainWhere((p) => files.any((f) => f.path == p));
      });
      widget.onPathChanged(path);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = '$e';
        _loading = false;
        _pathCtrl.text = path;
      });
    }
  }

  void _goBack() {
    if (_back.isEmpty) return;
    _forward.add(_path);
    _open(_back.removeLast(), record: false);
  }

  void _goForward() {
    if (_forward.isEmpty) return;
    _back.add(_path);
    _open(_forward.removeLast(), record: false);
  }

  void _goUp() {
    final up = _src.parent(_path);
    if (up != _path) _open(up);
  }

  /// 排序后的文件（目录始终在前）
  List<FileEntry> get _sorted {
    final list = List.of(_files);
    int cmp(FileEntry a, FileEntry b) => switch (_sortBy) {
      _SortBy.name => a.name.toLowerCase().compareTo(b.name.toLowerCase()),
      _SortBy.size => a.size.compareTo(b.size),
      _SortBy.modified => (a.modified ?? 0).compareTo(b.modified ?? 0),
    };
    list.sort((a, b) {
      if (a.isDir != b.isDir) return a.isDir ? -1 : 1;
      return _asc ? cmp(a, b) : cmp(b, a);
    });
    return list;
  }

  void _sort(_SortBy by) => setState(() {
    if (_sortBy == by) {
      _asc = !_asc;
    } else {
      _sortBy = by;
      _asc = true;
    }
  });

  /// 点击选择：Ctrl / Cmd 多选，Shift 连续选择
  void _select(List<FileEntry> list, int i) {
    final k = HardwareKeyboard.instance;
    final f = list[i];
    setState(() {
      if (k.isShiftPressed && _anchor != null && _anchor! < list.length) {
        final a = _anchor! < i ? _anchor! : i;
        final b = _anchor! < i ? i : _anchor!;
        _selected
          ..clear()
          ..addAll(list.sublist(a, b + 1).map((e) => e.path));
      } else if (k.isControlPressed || k.isMetaPressed) {
        if (!_selected.remove(f.path)) _selected.add(f.path);
        _anchor = i;
      } else {
        _selected
          ..clear()
          ..add(f.path);
        _anchor = i;
      }
    });
  }

  Future<void> _mkdir() async {
    final name = await UiUtils.prompt(context, title: context.tr('sftp.mkdir'), label: context.tr('sftp.name'));
    if (name == null || name.trim().isEmpty) return;
    await _run(() => _src.mkdir(_src.join(_path, name.trim())));
  }

  Future<void> _rename(FileEntry f) async {
    final name = await UiUtils.prompt(
      context,
      title: context.tr('common.rename'),
      label: context.tr('sftp.name'),
      initial: f.name,
    );
    if (name == null || name.trim().isEmpty || name == f.name) return;
    await _run(() => _src.rename(f.path, _src.join(_path, name.trim())));
  }

  Future<void> _delete(List<FileEntry> files) async {
    if (files.isEmpty) return;
    final ok = await UiUtils.confirm(
      context,
      title: context.tr(_src.isRemote ? 'sftp.delete.remote' : 'sftp.delete.local'),
      message: context.tr('sftp.delete.message', {
        'name': files.length == 1 ? files.first.path : context.tr('sftp.items', {'n': files.length}),
      }),
      danger: true,
    );
    if (!ok) return;
    await _run(() async {
      for (final f in files) {
        await _src.delete(f);
      }
    });
  }

  /// 执行文件操作并刷新，失败时提示
  Future<void> _run(Future<void> Function() op) async {
    try {
      await op();
    } catch (e) {
      UiUtils.toast('$e', error: true);
    }
    await refresh();
  }

  Future<void> _menu(FileEntry f, Offset pos) async {
    if (!_selected.contains(f.path)) {
      setState(() {
        _selected
          ..clear()
          ..add(f.path);
      });
    }
    final targets = selection;
    final extra = widget.extraMenu?.call(context) ?? const [];
    final r = await AppMenu.showAt<Object>(context, pos, [
      if (f.isDir && targets.length == 1) AppMenuItem(value: 'open', label: context.tr('sftp.open')),
      AppMenuItem(value: 'transfer', label: widget.transferLabel),
      if (targets.length == 1) AppMenuItem(value: 'rename', label: context.tr('common.rename')),
      AppMenuItem(value: 'copy', label: context.tr('sftp.copy_path')),
      for (var i = 0; i < extra.length; i++)
        if (targets.length == 1 && extra[i].$2(f)) AppMenuItem(value: i, label: extra[i].$1),
      const AppMenuDivider(),
      AppMenuItem(value: 'delete', label: context.tr('common.delete'), danger: true),
    ]);
    switch (r) {
      case 'open':
        _open(f.path);
      case 'transfer':
        widget.onTransfer(targets);
      case 'rename':
        _rename(f);
      case 'copy':
        Clipboard.setData(ClipboardData(text: targets.map((e) => e.path).join('\n')));
        UiUtils.toast(S.of(UiUtils.context!).t('common.copied'));
      case 'delete':
        _delete(targets);
      case final int i:
        extra[i].$3(f);
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    Widget body = DragTarget<FilePaneDrag>(
      // 只接受另一栏拖来的文件，避免同栏拖动被当作传输
      onWillAcceptWithDetails: (d) => d.data.fromRemote != _src.isRemote,
      onAcceptWithDetails: (d) => widget.onTransfer(d.data.files),
      builder: (context, candidates, _) => Container(
        decoration: BoxDecoration(
          color: p.panel,
          borderRadius: BorderRadius.circular(AppSizes.radiusLarge),
          border: Border.all(
            color: candidates.isNotEmpty || _dropHover ? p.accent : p.border,
            width: candidates.isNotEmpty || _dropHover ? 1.5 : 1,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _header(context),
            _navBar(context),
            Expanded(child: _table(context)),
          ],
        ),
      ),
    );
    if (widget.onExternalDrop != null) {
      body = FileDropTarget(
        onDragEntered: (_) => setState(() => _dropHover = true),
        onDragExited: (_) => setState(() => _dropHover = false),
        onDragDone: (d) {
          setState(() => _dropHover = false);
          widget.onExternalDrop!(d.files.map((f) => f.path).toList());
        },
        child: body,
      );
    }
    return body;
  }

  /// 标题行：图标、名称、状态、传输与新建文件夹
  Widget _header(BuildContext context) {
    final p = context.palette;
    final sel = selection;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 12, 8),
      child: Row(
        children: [
          Icon(widget.icon, size: 20, color: p.text),
          const SizedBox(width: 10),
          Expanded(
            child: Row(
              children: [
                Flexible(
                  child: Text(
                    widget.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: p.text),
                  ),
                ),
                if (widget.status != null) ...[const SizedBox(width: 10), widget.status!],
              ],
            ),
          ),
          ToolButton(
            compact: true,
            icon: widget.transferIcon,
            label: widget.transferLabel,
            onPressed: sel.isEmpty ? null : () => widget.onTransfer(sel),
          ),
          const SizedBox(width: 6),
          ToolButton(
            compact: true,
            icon: Icons.create_new_folder_outlined,
            tooltip: context.tr('sftp.mkdir'),
            onPressed: _error != null && _files.isEmpty ? null : _mkdir,
          ),
        ],
      ),
    );
  }

  /// 导航行：后退、前进、上级、刷新、路径
  Widget _navBar(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 0, 12, 10),
      child: Row(
        children: [
          GhostIconButton(
            icon: Icons.arrow_back,
            tooltip: context.tr('sftp.back'),
            onPressed: _back.isEmpty ? null : _goBack,
          ),
          GhostIconButton(
            icon: Icons.arrow_forward,
            tooltip: context.tr('sftp.forward'),
            onPressed: _forward.isEmpty ? null : _goForward,
          ),
          GhostIconButton(icon: Icons.arrow_upward, tooltip: context.tr('sftp.up'), onPressed: _goUp),
          GhostIconButton(
            icon: Icons.refresh,
            tooltip: context.tr('common.refresh'),
            onPressed: () => _open(_path, record: false),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: SizedBox(
              height: AppSizes.controlCompact + 2,
              child: TextField(
                controller: _pathCtrl,
                style: const TextStyle(fontSize: 13, fontFamily: 'monospace'),
                decoration: const InputDecoration(contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 8)),
                onSubmitted: (v) => _open(v.trim()),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _table(BuildContext context) {
    final p = context.palette;
    return LayoutBuilder(
      builder: (context, box) {
        final showTime = box.maxWidth >= 380;
        final cols = [
          AppColumn(context.tr('sftp.name'), flex: 1),
          AppColumn(context.tr('sftp.size'), width: 84),
          if (showTime) AppColumn(context.tr('sftp.modified'), width: 140),
        ];
        Widget arrow(_SortBy by) => _sortBy == by
            ? Icon(_asc ? Icons.arrow_drop_up : Icons.arrow_drop_down, size: 18, color: p.textMuted)
            : const SizedBox.shrink();
        final header = Container(
          height: 36,
          padding: const EdgeInsets.symmetric(horizontal: 8),
          decoration: BoxDecoration(
            border: Border(
              top: BorderSide(color: p.border),
              bottom: BorderSide(color: p.border),
            ),
          ),
          child: AppTableCells(
            columns: cols,
            cells: [
              for (final (i, by) in [(0, _SortBy.name), (1, _SortBy.size), if (showTime) (2, _SortBy.modified)])
                InkWell(
                  onTap: () => _sort(by),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Flexible(
                        child: Text(
                          cols[i].label,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(fontSize: 13, color: p.textMuted),
                        ),
                      ),
                      arrow(by),
                    ],
                  ),
                ),
            ],
          ),
        );
        Widget content;
        if (_loading) {
          content = const Center(
            child: SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2)),
          );
        } else if (_error != null) {
          content = Center(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.error_outline, color: p.danger),
                  const SizedBox(height: 8),
                  Text(
                    _error!,
                    textAlign: TextAlign.center,
                    style: TextStyle(color: p.danger, fontSize: 13),
                  ),
                  const SizedBox(height: 12),
                  OutlinedButton(onPressed: () => _open(_path, record: false), child: Text(context.tr('common.retry'))),
                ],
              ),
            ),
          );
        } else {
          final list = _sorted;
          final parent = _src.parent(_path);
          final hasParent = parent != _path;
          content = ListView.builder(
            itemExtent: 38,
            itemCount: list.length + (hasParent ? 1 : 0),
            itemBuilder: (context, idx) {
              if (hasParent && idx == 0) {
                return AppTableRow(
                  height: 38,
                  padding: 8,
                  divider: false,
                  columns: cols,
                  onDoubleTap: _goUp,
                  cells: [
                    _nameCell(context, '..', Icons.folder, p.folder),
                    Text('—', style: TextStyle(color: p.textFaint)),
                    if (showTime) Text('—', style: TextStyle(color: p.textFaint)),
                  ],
                );
              }
              final i = idx - (hasParent ? 1 : 0);
              final f = list[i];
              final selected = _selected.contains(f.path);
              final row = AppTableRow(
                height: 38,
                padding: 8,
                divider: false,
                columns: cols,
                selected: selected,
                onTap: () => _select(list, i),
                onDoubleTap: () => f.isDir ? _open(f.path) : widget.onTransfer([f]),
                onSecondaryTapUp: (d) => _menu(f, d.globalPosition),
                cells: [
                  _nameCell(
                    context,
                    f.name,
                    f.isDir ? Icons.folder : (f.isLink ? Icons.link : Icons.description_outlined),
                    f.isDir ? p.folder : p.textMuted,
                  ),
                  Text(
                    f.isDir ? '—' : FormatUtils.bytes(f.size),
                    maxLines: 1,
                    style: TextStyle(fontSize: 13, color: p.textMuted),
                  ),
                  if (showTime)
                    Text(
                      FormatUtils.unixTime(f.modified),
                      maxLines: 1,
                      style: TextStyle(fontSize: 13, color: p.textMuted, fontFamily: 'monospace'),
                    ),
                ],
              );
              // 拖动到另一栏即传输；拖动选中项时带上全部选中文件
              return Draggable<FilePaneDrag>(
                data: FilePaneDrag(fromRemote: _src.isRemote, files: selected ? selection : [f]),
                feedback: _DragFeedback(count: selected ? _selected.length : 1, name: f.name),
                child: row,
              );
            },
          );
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            header,
            Expanded(child: content),
          ],
        );
      },
    );
  }

  Widget _nameCell(BuildContext context, String name, IconData icon, Color color) {
    return Row(
      children: [
        Icon(icon, size: 20, color: color),
        const SizedBox(width: 10),
        Flexible(
          child: Text(name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 14)),
        ),
      ],
    );
  }
}

/// 拖动时跟随指针的提示
class _DragFeedback extends StatelessWidget {
  const _DragFeedback({required this.count, required this.name});

  final int count;
  final String name;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Material(
      color: Colors.transparent,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: p.panelRaised,
          borderRadius: BorderRadius.circular(AppSizes.radius),
          border: Border.all(color: p.accent),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.description_outlined, size: 18, color: p.accent),
            const SizedBox(width: 8),
            Text(
              count > 1 ? context.tr('sftp.items', {'n': count}) : name,
              style: TextStyle(fontSize: 13, color: p.text),
            ),
          ],
        ),
      ),
    );
  }
}
