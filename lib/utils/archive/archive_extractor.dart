import 'dart:io';

import 'archive_extractor_posix.dart';
import 'archive_extractor_windows.dart';

/// 压缩包解压（.tar.gz / .zip）：调用系统自带的解压工具，能正确还原符号链接与可执行权限。
/// 每个平台各自实现，修改时所有平台需要一起改。
abstract class ArchiveExtractor {
  /// 当前平台的实现
  factory ArchiveExtractor.current() => Platform.isWindows ? WindowsArchiveExtractor() : PosixArchiveExtractor();

  /// 解压 [archive] 到已存在的目录 [dest]，失败时抛出 [ProcessException]
  Future<void> extract(File archive, Directory dest);
}
