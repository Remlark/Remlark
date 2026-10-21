import 'dart:io';

import 'archive_extractor_posix.dart';
import 'archive_extractor_windows.dart';

/// 压缩包解压（.tar.gz / .zip）：POSIX 使用系统工具保留权限，Windows 使用 Dart 流式解压。
/// 每个平台各自实现，修改时所有平台需要一起改。
abstract class ArchiveExtractor {
  /// 当前平台的实现
  factory ArchiveExtractor.current() =>
      Platform.isWindows ? WindowsArchiveExtractor() : PosixArchiveExtractor();

  /// 解压 [archive] 到已存在的目录 [dest]，失败时抛出 [ProcessException]
  Future<void> extract(File archive, Directory dest);
}
