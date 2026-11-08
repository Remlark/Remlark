import '../../modules/sftp/sftp_service.dart';
import 'file_drag_out.dart';
import 'file_drag_out_channel.dart';

/// Windows：原生 OLE 虚拟文件（CFSTR_FILEDESCRIPTORW + CFSTR_FILECONTENTS）。
/// 资源管理器需要事先知道全部文件和目录，因此拖动开始前递归列出目录；
/// 目录由资源管理器按描述创建，放下后逐个文件请求写入临时文件再复制
class WindowsFileDragOut extends ChannelFileDragOut {
  WindowsFileDragOut({super.channel});

  @override
  Future<List<DragOutEntry>> buildEntries(DragOutSource source) async {
    final result = <DragOutEntry>[];
    final dirs = <String>{};

    /// 先补齐路径上的各级目录（资源管理器要求父目录描述在子项之前）
    void addDirs(String rel, FileEntry owner) {
      final parts = rel.split('/');
      for (var i = 1; i < parts.length; i++) {
        final dir = parts.sublist(0, i).join('/');
        if (dirs.add(dir)) result.add(DragOutEntry(path: dir, isDir: true, size: 0, file: owner));
      }
    }

    for (final item in source.items) {
      if (!item.isDir) {
        result.add(DragOutEntry(path: item.name, isDir: false, size: item.size, file: item));
        continue;
      }
      // 顶层目录即使为空也要出现
      if (dirs.add(item.name)) result.add(DragOutEntry(path: item.name, isDir: true, size: 0, file: item));
      for (final (f, rel) in await source.walk(item)) {
        addDirs(rel, item);
        result.add(DragOutEntry(path: rel, isDir: false, size: f.size, file: f));
      }
    }
    return result;
  }
}
