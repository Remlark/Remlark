import 'dart:io';
import 'dart:isolate';

import 'package:archive/archive_io.dart';

import 'archive_extractor.dart';

/// Windows：使用 Dart 流式解压，避开系统 bsdtar 在 ARM64 上的 Unicode 文件名缺陷。
class WindowsArchiveExtractor implements ArchiveExtractor {
  @override
  Future<void> extract(File archive, Directory dest) async {
    final source = archive.path;
    final output = dest.path;
    try {
      // 大型 Codex / Node 包在独立 isolate 中按流写盘，避免阻塞界面或整包读入内存。
      await Isolate.run(() => extractFileToDisk(source, output));
    } catch (error) {
      // 统一接口的错误类型，让安装器沿用原有的失败回滚流程。
      throw ProcessException('archive', [source], '$error', 1);
    }
  }
}
