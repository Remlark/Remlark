import 'package:flutter/material.dart';

import '../../../app/theme/app_palette.dart';
import '../../../l10n/app_localizations.dart';
import '../../../utils/format_utils.dart';
import '../../sftp/transfer_manager.dart';
import '../../sftp/ui/transfer_list.dart';

/// 终端状态栏右侧的上传状态：显示当前上传文件、进度与速度；全部结束后显示完成 / 失败。
/// 点击弹出上传详情（可取消、重试、移除）。没有任务时不占位
class UploadStatus extends StatefulWidget {
  const UploadStatus({super.key, required this.manager});

  final TransferManager manager;

  @override
  State<UploadStatus> createState() => _UploadStatusState();
}

class _UploadStatusState extends State<UploadStatus> {
  final _portal = OverlayPortalController();
  final _link = LayerLink();

  /// 弹层宽度
  static const _popupWidth = 360.0;

  void _toggle() => _portal.isShowing ? _portal.hide() : _portal.show();

  @override
  Widget build(BuildContext context) {
    // 外层监听任务增删与状态变化，内层监听各任务的进度
    return ListenableBuilder(
      listenable: widget.manager,
      builder: (context, _) {
        final tasks = widget.manager.tasks;
        if (tasks.isEmpty) {
          // 任务全部移除后关闭弹层（在帧结束后执行，避免构建期间改动 Overlay）
          if (_portal.isShowing) WidgetsBinding.instance.addPostFrameCallback((_) => _portal.hide());
          return const SizedBox.shrink();
        }
        return OverlayPortal(
          controller: _portal,
          overlayChildBuilder: _popup,
          child: CompositedTransformTarget(
            link: _link,
            child: ListenableBuilder(
              listenable: Listenable.merge(tasks),
              builder: (context, _) => _summary(context, tasks),
            ),
          ),
        );
      },
    );
  }

  /// 状态栏中的摘要
  Widget _summary(BuildContext context, List<TransferTask> tasks) {
    final p = context.palette;
    final style = TextStyle(fontSize: 12.5, color: p.textMuted);
    final active = tasks.where((t) => t.isActive).toList();
    // 队列按插入倒序保存，最早排队的活跃任务即正在执行的任务
    final current = active.lastOrNull;
    final failed = tasks.where((t) => t.isFailed).length;
    final List<Widget> children;
    if (current != null) {
      children = [
        Icon(Icons.upload_rounded, size: 15, color: p.accent),
        const SizedBox(width: 6),
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 220),
          child: Text(
            context.tr('upload.status.running', {'name': current.name}),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: style.copyWith(color: p.text),
          ),
        ),
        // 还有排队中的任务时显示数量
        if (active.length > 1) Text(' +${active.length - 1}', style: style),
        const SizedBox(width: 8),
        SizedBox(
          width: 100,
          child: LinearProgressIndicator(
            value: current.status == TransferStatus.running ? current.progress : null,
            minHeight: 4,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        const SizedBox(width: 8),
        Text(
          current.status == TransferStatus.running
              ? '${(current.progress * 100).floor()}% · ${FormatUtils.speed(current.speed)}'
              : context.tr('transfer.queued'),
          style: style.copyWith(fontFamily: 'monospace'),
        ),
      ];
    } else if (failed > 0) {
      children = [
        Icon(Icons.error_outline, size: 15, color: p.danger),
        const SizedBox(width: 6),
        Text(context.tr('upload.status.failed', {'count': failed}), style: style.copyWith(color: p.danger)),
      ];
    } else {
      children = [
        Icon(Icons.check_circle_outline, size: 15, color: p.success),
        const SizedBox(width: 6),
        Text(context.tr('upload.status.done'), style: style.copyWith(color: p.success)),
      ];
    }
    // 与弹层同组：点击摘要不算“点击外部”，由 _toggle 负责开关
    return TapRegion(
      groupId: _link,
      child: Tooltip(
        message: context.tr('upload.status.details'),
        child: InkWell(
          onTap: _toggle,
          borderRadius: BorderRadius.circular(4),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
            child: Row(mainAxisSize: MainAxisSize.min, children: children),
          ),
        ),
      ),
    );
  }

  /// 上传详情弹层：右对齐显示在状态栏上方，点击外部关闭
  Widget _popup(BuildContext context) {
    final p = context.palette;
    return CompositedTransformFollower(
      link: _link,
      targetAnchor: Alignment.topRight,
      followerAnchor: Alignment.bottomRight,
      offset: const Offset(0, -6),
      child: Align(
        alignment: Alignment.bottomRight,
        child: TapRegion(
          groupId: _link,
          onTapOutside: (_) => _portal.hide(),
          child: SizedBox(
            width: _popupWidth,
            child: Material(
              elevation: 6,
              color: p.panelRaised,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
                side: BorderSide(color: p.borderStrong),
              ),
              clipBehavior: Clip.antiAlias,
              child: TransferList(manager: widget.manager, maxHeight: 240),
            ),
          ),
        ),
      ),
    );
  }
}
