import 'file_drag_out.dart';
import 'file_drag_out_channel.dart';

/// macOS：原生 NSFilePromiseProvider，每个顶层文件 / 目录一个 promise，
/// Finder 放下后给出目标路径，再整体下载（目录递归）
class MacFileDragOut extends ChannelFileDragOut {
  MacFileDragOut({super.channel});

  @override
  Future<List<DragOutEntry>> buildEntries(DragOutSource source) async => [
    for (final f in source.items) DragOutEntry(path: f.name, isDir: f.isDir, size: f.size, file: f),
  ];
}
