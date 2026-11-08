import 'dart:io';

import '../../modules/sftp/sftp_service.dart';
import 'file_drag_out_macos.dart';
import 'file_drag_out_windows.dart';

/// 拖出到系统文件管理器的远程文件，以及按需取回文件的方法
class DragOutSource {
  const DragOutSource({required this.items, required this.walk, required this.fetch});

  /// 拖动的顶层文件 / 目录
  final List<FileEntry> items;

  /// 递归列出远程目录下的所有文件：(文件, 以 / 分隔、含顶层目录名的相对路径)
  final Future<List<(FileEntry file, String rel)>> Function(FileEntry dir) walk;

  /// 把远程文件或目录下载到本地完整路径 [localPath]（名称以该路径为准），完成后返回，失败抛出异常
  final Future<void> Function(FileEntry entry, String localPath) fetch;
}

/// 拖出时交给原生层的一项：相对路径（/ 分隔）、是否目录、大小
class DragOutEntry {
  const DragOutEntry({required this.path, required this.isDir, required this.size, required this.file});

  final String path;
  final bool isDir;
  final int size;

  /// 对应的远程文件；原生层请求写入时据此下载
  final FileEntry file;

  Map<String, Object> toMap() => {'path': path, 'isDir': isDir, 'size': size};
}

/// 把应用内的远程文件拖到系统文件管理器（Finder / 资源管理器），放下时才下载到放下的位置。
/// 跨平台接口：macOS 用 file promise，Windows 用 OLE 虚拟文件，各自在原生层实现；
/// Linux 不支持（XDS 协议只能拖单个文件且 Wayland 不可用），[supported] 为 false
abstract class FileDragOut {
  /// 当前平台的实现
  static final FileDragOut instance = Platform.isMacOS
      ? MacFileDragOut()
      : Platform.isWindows
      ? WindowsFileDragOut()
      : UnsupportedFileDragOut();

  /// 当前平台是否支持拖出
  bool get supported;

  /// 开始系统拖动（应在鼠标仍按下、指针离开窗口时调用），返回是否已开始
  Future<bool> start(DragOutSource source);
}

/// 不支持拖出的平台（Linux 等）
class UnsupportedFileDragOut extends FileDragOut {
  @override
  bool get supported => false;

  @override
  Future<bool> start(DragOutSource source) async => false;
}
