import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../../../app/theme/app_palette.dart';
import '../file_kind.dart';
import '../sftp_service.dart';

/// 文件类型图标：目录使用主题色文件夹图标，其余文件按 [FileKind] 显示对应的 SVG
class FileTypeIcon extends StatelessWidget {
  const FileTypeIcon({super.key, required this.kind, this.isDir = false, this.size = 20});

  /// 按文件条目构建图标（指向目录的链接按目录显示）
  FileTypeIcon.entry(FileEntry f, {Key? key, double size = 20})
    : this(key: key, kind: FileKind.of(f), isDir: f.isDir, size: size);

  /// 仅有文件名时构建图标，如传输队列
  FileTypeIcon.name(String name, {Key? key, bool isDir = false, double size = 20})
    : this(key: key, kind: FileKind.fromName(name), isDir: isDir, size: size);

  final FileKind kind;
  final bool isDir;
  final double size;

  @override
  Widget build(BuildContext context) {
    if (isDir) return Icon(Icons.folder, size: size, color: context.palette.folder);
    return SvgPicture.asset(kind.asset, width: size, height: size);
  }
}
