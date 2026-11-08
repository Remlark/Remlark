import 'package:flutter/material.dart';

import '../../../app/theme/app_palette.dart';
import '../../../app/theme/app_theme.dart';
import '../../../l10n/app_localizations.dart';
import '../../../ui_kit/app_table.dart';
import '../../../ui_kit/buttons.dart';
import '../../../utils/format_utils.dart';
import '../transfer_manager.dart';
import 'file_type_icon.dart';

/// 传输队列分类
enum _QueueTab { active, done, failed }

/// SFTP 底部传输队列：进行中 / 已完成 / 失败三个分类，表格显示方向、来源、目标、进度、速度、剩余时间，
/// 进行中可取消、失败可重试；可折叠以腾出浏览空间
class TransferQueue extends StatefulWidget {
  const TransferQueue({
    super.key,
    required this.manager,
    required this.hostName,
    required this.collapsed,
    required this.onCollapse,
  });

  final TransferManager manager;

  /// 远程主机名（远程路径显示为 host:/path）
  final String hostName;
  final bool collapsed;
  final ValueChanged<bool> onCollapse;

  @override
  State<TransferQueue> createState() => _TransferQueueState();
}

class _TransferQueueState extends State<TransferQueue> {
  _QueueTab _tab = _QueueTab.active;

  bool _match(TransferTask t, _QueueTab tab) => switch (tab) {
    _QueueTab.active => t.isActive,
    _QueueTab.done => t.status == TransferStatus.done,
    _QueueTab.failed => t.isFailed,
  };

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return ListenableBuilder(
      listenable: widget.manager,
      builder: (context, _) {
        final tasks = widget.manager.tasks;
        int count(_QueueTab t) => tasks.where((e) => _match(e, t)).length;
        final shown = tasks.where((e) => _match(e, _tab)).toList();
        return Container(
          decoration: BoxDecoration(
            color: p.panel,
            borderRadius: BorderRadius.circular(AppSizes.radiusLarge),
            border: Border.all(color: p.border),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SizedBox(
                height: 46,
                child: Row(
                  children: [
                    const SizedBox(width: 8),
                    for (final (t, key) in [
                      (_QueueTab.active, 'transfer.tab.active'),
                      (_QueueTab.done, 'transfer.tab.done'),
                      (_QueueTab.failed, 'transfer.tab.failed'),
                    ])
                      _TabLabel(
                        text: '${context.tr(key)} (${count(t)})',
                        selected: _tab == t && !widget.collapsed,
                        onTap: () {
                          setState(() => _tab = t);
                          if (widget.collapsed) widget.onCollapse(false);
                        },
                      ),
                    const Spacer(),
                    if (count(_QueueTab.done) > 0)
                      TextButton.icon(
                        style: TextButton.styleFrom(foregroundColor: p.textMuted),
                        icon: const Icon(Icons.delete_sweep_outlined, size: 18),
                        label: Text(context.tr('transfer.clear')),
                        onPressed: widget.manager.clearFinished,
                      ),
                    GhostIconButton(
                      icon: widget.collapsed ? Icons.expand_less : Icons.expand_more,
                      tooltip: context.tr(widget.collapsed ? 'transfer.expand' : 'transfer.collapse'),
                      onPressed: () => widget.onCollapse(!widget.collapsed),
                    ),
                    const SizedBox(width: 6),
                  ],
                ),
              ),
              if (!widget.collapsed) SizedBox(height: 176, child: _table(context, shown)),
            ],
          ),
        );
      },
    );
  }

  Widget _table(BuildContext context, List<TransferTask> shown) {
    final p = context.palette;
    return LayoutBuilder(
      builder: (context, box) {
        final wide = box.maxWidth >= 1000;
        final mid = box.maxWidth >= 680;
        final cols = [
          AppColumn(context.tr('transfer.col.name'), flex: 3),
          if (mid) AppColumn(context.tr('transfer.col.direction'), width: 124),
          if (wide) AppColumn(context.tr('transfer.col.source'), flex: 4),
          if (wide) AppColumn(context.tr('transfer.col.target'), flex: 4),
          AppColumn(context.tr('transfer.col.progress'), width: mid ? 170 : 130),
          if (mid) AppColumn(context.tr('transfer.col.speed'), width: 96),
          if (mid) AppColumn(context.tr('transfer.col.remaining'), width: 84),
          AppColumn(context.tr('transfer.col.action'), width: 84),
        ];
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              decoration: BoxDecoration(
                border: Border(top: BorderSide(color: p.border)),
              ),
              child: AppTableHeader(columns: cols, height: 36),
            ),
            Expanded(
              child: shown.isEmpty
                  ? Center(
                      child: Text(context.tr('transfer.empty'), style: TextStyle(color: p.textFaint, fontSize: 13)),
                    )
                  : ListView.builder(
                      itemCount: shown.length,
                      itemBuilder: (context, i) => ListenableBuilder(
                        listenable: shown[i],
                        builder: (context, _) => _row(context, cols, shown[i], wide: wide, mid: mid),
                      ),
                    ),
            ),
          ],
        );
      },
    );
  }

  Widget _row(BuildContext context, List<AppColumn> cols, TransferTask t, {required bool wide, required bool mid}) {
    final p = context.palette;
    final up = t.direction == TransferDirection.upload;
    final muted = TextStyle(fontSize: 13, color: p.textMuted);
    final mono = TextStyle(fontSize: 12.5, color: p.textMuted, fontFamily: 'monospace');
    final remote = '${widget.hostName}:';
    final pct = (t.progress * 100).round();
    final progress = switch (t.status) {
      TransferStatus.done => Text(context.tr('transfer.done'), style: TextStyle(fontSize: 13, color: p.success)),
      TransferStatus.failed => Tooltip(
        message: t.error ?? '',
        child: Text(
          t.error ?? context.tr('transfer.failed'),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(fontSize: 13, color: p.danger),
        ),
      ),
      TransferStatus.cancelled => Text(context.tr('transfer.cancelled'), style: muted),
      TransferStatus.queued => Text(context.tr('transfer.queued'), style: muted),
      TransferStatus.running => Row(
        children: [
          SizedBox(width: 38, child: Text('$pct%', style: muted)),
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(3),
              child: LinearProgressIndicator(value: t.progress, minHeight: 6, color: p.accent),
            ),
          ),
        ],
      ),
    };
    return AppTableRow(
      height: 44,
      columns: cols,
      cells: [
        Row(
          children: [
            // 下载目录或多文件任务显示文件夹，其余按文件名显示类型图标
            FileTypeIcon.name(t.name, isDir: (t.remote?.isDir ?? false) || t.fileCount > 1, size: 18),
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                t.fileCount > 1 ? '${t.name}  ${t.filesDone}/${t.fileCount}' : t.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 13.5),
              ),
            ),
          ],
        ),
        if (mid)
          Row(
            children: [
              Icon(
                up ? Icons.arrow_circle_up_rounded : Icons.arrow_circle_down_rounded,
                size: 18,
                color: up ? p.accent : p.info,
              ),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  context.tr(up ? 'transfer.dir.up' : 'transfer.dir.down'),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: muted,
                ),
              ),
            ],
          ),
        if (wide) Text(up ? t.source : '$remote${t.source}', maxLines: 1, overflow: TextOverflow.ellipsis, style: mono),
        if (wide) Text(up ? '$remote${t.target}' : t.target, maxLines: 1, overflow: TextOverflow.ellipsis, style: mono),
        progress,
        if (mid) Text(t.status == TransferStatus.running ? FormatUtils.speed(t.speed) : '—', style: muted),
        if (mid) Text(t.remaining == null ? '—' : FormatUtils.duration(t.remaining!), style: mono),
        if (t.isActive)
          _RowAction(label: context.tr('common.cancel'), onPressed: () => widget.manager.cancel(t))
        else if (t.isFailed)
          _RowAction(label: context.tr('common.retry'), onPressed: () => widget.manager.retry(t))
        else
          const SizedBox.shrink(),
      ],
    );
  }
}

/// 队列分类标签（下划线样式）
class _TabLabel extends StatelessWidget {
  const _TabLabel({required this.text, required this.selected, required this.onTap});

  final String text;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14),
        decoration: BoxDecoration(
          border: Border(bottom: BorderSide(color: selected ? p.accent : Colors.transparent, width: 2)),
        ),
        alignment: Alignment.center,
        child: Text(
          text,
          style: TextStyle(
            fontSize: 14,
            color: selected ? p.accent : p.textMuted,
            fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
          ),
        ),
      ),
    );
  }
}

/// 行内操作按钮（取消 / 重试）
class _RowAction extends StatelessWidget {
  const _RowAction({required this.label, required this.onPressed});

  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 30,
      child: OutlinedButton(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(0, 30),
          padding: const EdgeInsets.symmetric(horizontal: 12),
        ),
        onPressed: onPressed,
        child: Text(label, style: const TextStyle(fontSize: 13)),
      ),
    );
  }
}
