import 'package:desktop_drop/desktop_drop.dart';
import 'package:flutter/material.dart';

/// 文件拖放区域：只在自身真正可见、且没有被对话框遮住时接收拖放。
///
/// desktop_drop 的 [DropTarget] 全局监听拖放事件、只按坐标判断是否落在自身范围内，
/// 隐藏的页面（IndexedStack）、工作区中未显示的会话（Visibility）以及对话框下层的组件也会收到，
/// 导致一次拖放被多个窗口同时处理（如拖给 RDP 时，同位置隐藏的 SSH 终端也开始上传）。
/// 拖动中被禁用时 DropTarget 会回调 [onDragExited]，拖放提示不会残留
class FileDropTarget extends StatelessWidget {
  const FileDropTarget({
    super.key,
    required this.child,
    this.onDragEntered,
    this.onDragExited,
    this.onDragUpdated,
    this.onDragDone,
  });

  final Widget child;
  final void Function(DropEventDetails details)? onDragEntered;
  final void Function(DropEventDetails details)? onDragExited;
  final void Function(DropEventDetails details)? onDragUpdated;
  final void Function(DropDoneDetails details)? onDragDone;

  @override
  Widget build(BuildContext context) => DropTarget(
    // Visibility.of 综合所有祖先（IndexedStack 页面、工作区会话）；ModalRoute 判断是否被对话框遮住
    enable: Visibility.of(context) && (ModalRoute.isCurrentOf(context) ?? true),
    onDragEntered: onDragEntered,
    onDragExited: onDragExited,
    onDragUpdated: onDragUpdated,
    onDragDone: onDragDone,
    child: child,
  );
}
