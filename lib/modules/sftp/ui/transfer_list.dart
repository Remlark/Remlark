import 'package:flutter/material.dart';

import '../../../app/theme/app_palette.dart';
import '../../../l10n/app_localizations.dart';
import '../../../utils/format_utils.dart';
import '../transfer_manager.dart';

/// 传输列表：显示每个任务的进度、速度、状态，可取消、清除
class TransferList extends StatelessWidget {
  const TransferList({super.key, required this.manager, this.maxHeight = 180});

  final TransferManager manager;
  final double maxHeight;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: manager,
      builder: (context, _) {
        if (manager.tasks.isEmpty) return const SizedBox.shrink();
        final theme = Theme.of(context);
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 6, 4, 0),
              child: Row(
                children: [
                  Text(context.tr('transfer.title'), style: theme.textTheme.labelMedium),
                  const SizedBox(width: 6),
                  if (manager.activeCount > 0) Text('(${manager.activeCount})', style: theme.textTheme.labelSmall),
                  const Spacer(),
                  TextButton(onPressed: manager.clearFinished, child: Text(context.tr('transfer.clear'))),
                ],
              ),
            ),
            ConstrainedBox(
              constraints: BoxConstraints(maxHeight: maxHeight),
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: manager.tasks.length,
                itemBuilder: (context, i) => _TaskRow(task: manager.tasks[i], manager: manager),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _TaskRow extends StatelessWidget {
  const _TaskRow({required this.task, required this.manager});

  final TransferTask task;
  final TransferManager manager;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: task,
      builder: (context, _) {
        final t = task;
        final theme = Theme.of(context);
        final p = context.palette;
        final (statusText, color) = switch (t.status) {
          TransferStatus.queued => (context.tr('transfer.queued'), p.textFaint),
          TransferStatus.running => (
            '${FormatUtils.bytes(t.transferred)} / ${FormatUtils.bytes(t.total)} · ${FormatUtils.speed(t.speed)}',
            p.accent,
          ),
          TransferStatus.done => (context.tr('transfer.done'), p.success),
          TransferStatus.failed => (t.error ?? context.tr('transfer.failed'), p.danger),
          TransferStatus.cancelled => (context.tr('transfer.cancelled'), p.textFaint),
        };
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          child: Row(
            children: [
              Icon(t.direction == TransferDirection.upload ? Icons.upload : Icons.download, size: 16),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            t.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.bodySmall,
                          ),
                        ),
                        if (t.fileCount > 1) Text(' ${t.filesDone}/${t.fileCount}', style: theme.textTheme.labelSmall),
                      ],
                    ),
                    const SizedBox(height: 3),
                    LinearProgressIndicator(
                      value: t.status == TransferStatus.queued ? null : t.progress,
                      minHeight: 3,
                      borderRadius: BorderRadius.circular(2),
                      color: color,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      statusText,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.labelSmall?.copyWith(color: color),
                    ),
                  ],
                ),
              ),
              if (t.isActive)
                IconButton(
                  tooltip: context.tr('common.cancel'),
                  icon: const Icon(Icons.close, size: 16),
                  onPressed: () => manager.cancel(t),
                ),
            ],
          ),
        );
      },
    );
  }
}
