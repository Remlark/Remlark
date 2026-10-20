import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../../app/app_services.dart';
import '../../../app/theme/app_palette.dart';
import '../../../app/theme/app_theme.dart';
import '../../../l10n/app_localizations.dart';
import '../../../ui_kit/buttons.dart';
import '../../../ui_kit/page_header.dart';
import '../../../ui_kit/panel.dart';
import '../../../ui_kit/tags.dart';
import '../../../utils/ui_utils.dart';
import '../snippet_model.dart';
import 'snippet_editor_dialog.dart';

/// 类型筛选
enum _KindFilter { all, text, action }

/// 快捷指令页：页头（新建）+ 工具栏（搜索、类型筛选、数量）+ 左侧列表 + 右侧详情
class SnippetsPage extends StatefulWidget {
  const SnippetsPage({super.key});

  @override
  State<SnippetsPage> createState() => _SnippetsPageState();
}

class _SnippetsPageState extends State<SnippetsPage> {
  List<SnippetEntry> _items = [];
  String? _selected;
  String _q = '';
  _KindFilter _filter = _KindFilter.all;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final v = await context.read<AppServices>().snippetRepo.list();
    if (!mounted) return;
    setState(() {
      _items = v;
      if (_selected == null || !v.any((s) => s.uuid == _selected)) _selected = v.firstOrNull?.uuid;
    });
  }

  /// 按搜索与类型过滤后的指令
  List<SnippetEntry> get _visible {
    final q = _q.trim().toLowerCase();
    return _items.where((s) {
      if (_filter == _KindFilter.text && s.isAction) return false;
      if (_filter == _KindFilter.action && !s.isAction) return false;
      return q.isEmpty || s.name.toLowerCase().contains(q) || s.content.toLowerCase().contains(q);
    }).toList();
  }

  bool get _filtering => _q.trim().isNotEmpty || _filter != _KindFilter.all;

  Future<void> _edit([SnippetEntry? s]) async {
    final r = await showDialog<SnippetEntry>(
      context: context,
      builder: (_) => SnippetEditorDialog(existing: s, nextOrder: _items.length),
    );
    if (r == null || !mounted) return;
    await context.read<AppServices>().snippetRepo.save(r);
    _selected = r.uuid;
    _load();
  }

  Future<void> _delete(SnippetEntry s) async {
    final ok = await UiUtils.confirm(context, title: context.tr('snippet.delete'), message: s.name, danger: true);
    if (!ok || !mounted) return;
    await context.read<AppServices>().snippetRepo.delete(s.uuid);
    _load();
  }

  /// 修改“自动回车”
  Future<void> _setAutoEnter(SnippetEntry s, bool v) async {
    await context.read<AppServices>().snippetRepo.save(
      SnippetEntry(uuid: s.uuid, name: s.name, content: s.content, kind: s.kind, autoEnter: v, sortOrder: s.sortOrder),
    );
    _load();
  }

  /// 拖动排序后重写 sortOrder
  Future<void> _reorder(int oldIndex, int newIndex) async {
    final list = List.of(_items);
    list.insert(newIndex, list.removeAt(oldIndex));
    setState(() => _items = list);
    final repo = context.read<AppServices>().snippetRepo;
    for (var i = 0; i < list.length; i++) {
      final s = list[i];
      if (s.sortOrder != i) {
        await repo.save(
          SnippetEntry(
            uuid: s.uuid,
            name: s.name,
            content: s.content,
            kind: s.kind,
            autoEnter: s.autoEnter,
            sortOrder: i,
          ),
        );
      }
    }
    _load();
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final visible = _visible;
    final selected = _items.where((s) => s.uuid == _selected).firstOrNull;
    return PageFrame(
      header: PageHeader(
        title: context.tr('nav.snippets'),
        subtitle: context.tr('snippet.page.subtitle'),
        actions: [
          FilledButton.icon(
            icon: const Icon(Icons.add, size: 18),
            label: Text(context.tr('snippet.new')),
            onPressed: () => _edit(),
          ),
        ],
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(AppSizes.pagePadding, 14, 24, 14),
            child: Row(
              children: [
                Flexible(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 400),
                    child: SearchField(
                      hint: context.tr('snippet.search.page'),
                      onChanged: (v) => setState(() => _q = v),
                    ),
                  ),
                ),
                const SizedBox(width: 16),
                PillChoice<_KindFilter>(
                  items: [
                    (_KindFilter.all, context.tr('common.all')),
                    (_KindFilter.text, context.tr('snippet.kind.short.text')),
                    (_KindFilter.action, context.tr('snippet.kind.short.action')),
                  ],
                  value: _filter,
                  onChanged: (v) => setState(() => _filter = v),
                ),
                const Spacer(),
                Text(
                  context.tr('snippet.count', {'n': visible.length}),
                  style: TextStyle(fontSize: 13, color: p.textMuted),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: _items.isEmpty
                ? EmptyState(
                    icon: Icons.terminal_rounded,
                    title: context.tr('snippet.empty'),
                    action: FilledButton.icon(
                      icon: const Icon(Icons.add, size: 18),
                      label: Text(context.tr('snippet.new')),
                      onPressed: () => _edit(),
                    ),
                  )
                : LayoutBuilder(
                    builder: (context, box) {
                      final detailWidth = (box.maxWidth * 0.46).clamp(320.0, 620.0);
                      return Row(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Expanded(child: _list(context, visible)),
                          SizedBox(
                            width: detailWidth,
                            child: Padding(
                              padding: const EdgeInsets.fromLTRB(0, 16, 20, 20),
                              child: selected == null
                                  ? const SizedBox.shrink()
                                  : _Detail(
                                      snippet: selected,
                                      onEdit: () => _edit(selected),
                                      onDelete: () => _delete(selected),
                                      onAutoEnter: (v) => _setAutoEnter(selected, v),
                                    ),
                            ),
                          ),
                        ],
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  /// 左侧列表：无筛选时可拖动图标排序
  Widget _list(BuildContext context, List<SnippetEntry> visible) {
    Widget item(SnippetEntry s, int i) => Padding(
      key: ValueKey(s.uuid),
      padding: const EdgeInsets.only(bottom: 10),
      child: _SnippetRow(
        snippet: s,
        selected: s.uuid == _selected,
        onTap: () => setState(() => _selected = s.uuid),
        onDoubleTap: () => _edit(s),
        dragHandle: _filtering ? null : (child) => ReorderableDragStartListener(index: i, child: child),
      ),
    );
    const padding = EdgeInsets.fromLTRB(20, 16, 16, 20);
    if (visible.isEmpty) {
      return Center(
        child: Text(context.tr('snippet.no_match'), style: TextStyle(color: context.palette.textFaint)),
      );
    }
    if (_filtering) {
      return ListView(padding: padding, children: [for (var i = 0; i < visible.length; i++) item(visible[i], i)]);
    }
    return ReorderableListView.builder(
      padding: padding,
      buildDefaultDragHandles: false,
      itemCount: visible.length,
      onReorderItem: _reorder,
      itemBuilder: (context, i) => item(visible[i], i),
    );
  }
}

/// 指令图标：动作类型使用终端图标，普通指令使用闪电图标
IconData _iconOf(SnippetEntry s) => s.isAction ? Icons.terminal_rounded : Icons.bolt_outlined;

/// 列表行
class _SnippetRow extends StatefulWidget {
  const _SnippetRow({
    required this.snippet,
    required this.selected,
    required this.onTap,
    required this.onDoubleTap,
    this.dragHandle,
  });

  final SnippetEntry snippet;
  final bool selected;
  final VoidCallback onTap;
  final VoidCallback onDoubleTap;

  /// 包装图标为拖动手柄
  final Widget Function(Widget child)? dragHandle;

  @override
  State<_SnippetRow> createState() => _SnippetRowState();
}

class _SnippetRowState extends State<_SnippetRow> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final s = widget.snippet;
    Widget icon = MouseRegion(
      cursor: widget.dragHandle == null ? MouseCursor.defer : SystemMouseCursors.grab,
      child: Tooltip(
        message: widget.dragHandle == null ? '' : context.tr('snippet.drag_hint'),
        child: Icon(_iconOf(s), size: 24, color: widget.selected ? p.accent : p.textMuted),
      ),
    );
    if (widget.dragHandle != null) icon = widget.dragHandle!(icon);
    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        onTap: widget.onTap,
        onDoubleTap: widget.onDoubleTap,
        child: Container(
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            color: widget.selected ? p.accentSoft : (_hover ? p.hover : p.panel),
            borderRadius: BorderRadius.circular(AppSizes.radiusLarge),
            border: Border.all(color: widget.selected ? p.accent.withValues(alpha: 0.6) : p.border),
          ),
          // 选中时左侧显示强调色竖条
          foregroundDecoration: widget.selected
              ? BoxDecoration(
                  border: Border(left: BorderSide(color: p.accent, width: 3)),
                )
              : null,
          padding: const EdgeInsets.fromLTRB(18, 14, 18, 14),
          child: Row(
            children: [
              icon,
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            s.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: p.text),
                          ),
                        ),
                        const SizedBox(width: 10),
                        _KindTag(snippet: s),
                      ],
                    ),
                    const SizedBox(height: 5),
                    Text(
                      s.isAction ? context.tr('snippet.kind.install_key.short') : s.content,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 13, color: p.textMuted, fontFamily: s.isAction ? null : 'monospace'),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 类型标签：命令 / 操作
class _KindTag extends StatelessWidget {
  const _KindTag({required this.snippet});

  final SnippetEntry snippet;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return snippet.isAction
        ? Tag(context.tr('snippet.kind.short.action'), color: p.info)
        : Tag(context.tr('snippet.kind.short.text'), color: p.accent);
  }
}

/// 右侧详情：命令内容（可复制）、选项、使用提示
class _Detail extends StatelessWidget {
  const _Detail({required this.snippet, required this.onEdit, required this.onDelete, required this.onAutoEnter});

  final SnippetEntry snippet;
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  final ValueChanged<bool> onAutoEnter;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final s = snippet;
    final label = TextStyle(fontSize: 13, color: p.textMuted, fontWeight: FontWeight.w500);
    return AppPanel(
      padding: const EdgeInsets.all(22),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Icon(_iconOf(s), size: 26, color: p.text),
                const SizedBox(width: 14),
                Expanded(
                  child: Row(
                    children: [
                      Flexible(
                        child: Text(
                          s.name,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: p.text),
                        ),
                      ),
                      const SizedBox(width: 10),
                      _KindTag(snippet: s),
                    ],
                  ),
                ),
                GhostIconButton(icon: Icons.delete_outline, tooltip: context.tr('snippet.delete'), onPressed: onDelete),
                const SizedBox(width: 6),
                ToolButton(
                  compact: true,
                  icon: Icons.edit_outlined,
                  label: context.tr('common.edit'),
                  onPressed: onEdit,
                ),
              ],
            ),
            const SizedBox(height: 18),
            const Divider(height: 1),
            const SizedBox(height: 18),
            if (s.isAction) ...[
              Text(context.tr('snippet.desc'), style: label),
              const SizedBox(height: 8),
              Text(
                context.tr('snippet.kind.install_key.desc'),
                style: TextStyle(fontSize: 14, color: p.text, height: 1.6),
              ),
            ] else ...[
              Text(context.tr('snippet.content'), style: label),
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.fromLTRB(14, 10, 6, 10),
                decoration: BoxDecoration(
                  color: p.input,
                  borderRadius: BorderRadius.circular(AppSizes.radius),
                  border: Border.all(color: p.borderStrong),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.only(top: 6),
                        child: SelectableText(
                          s.content,
                          maxLines: 8,
                          minLines: 1,
                          style: TextStyle(fontSize: 14, color: p.text, fontFamily: 'monospace'),
                        ),
                      ),
                    ),
                    GhostIconButton(
                      icon: Icons.copy_rounded,
                      tooltip: context.tr('common.copy'),
                      onPressed: () {
                        Clipboard.setData(ClipboardData(text: s.content));
                        UiUtils.toast(context.tr('common.copied'));
                      },
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 22),
              Text(context.tr('snippet.options'), style: label),
              const SizedBox(height: 6),
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          context.tr('snippet.auto_enter'),
                          style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: p.text),
                        ),
                        const SizedBox(height: 3),
                        Text(context.tr('snippet.auto_enter.desc'), style: TextStyle(fontSize: 13, color: p.textMuted)),
                      ],
                    ),
                  ),
                  Switch(value: s.autoEnter, onChanged: onAutoEnter),
                ],
              ),
            ],
            const SizedBox(height: 24),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: p.input,
                borderRadius: BorderRadius.circular(AppSizes.radius),
                border: Border.all(color: p.border),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.info_outline, size: 18, color: p.textMuted),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      context.tr('snippet.page.hint'),
                      style: TextStyle(fontSize: 13, color: p.textMuted, height: 1.6),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
