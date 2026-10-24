import 'dart:convert';
import 'dart:io';

/// 脚本文件统一使用 UTF-8；PowerShell 5.1 需要 BOM，POSIX shebang 需要位于文件开头。
class ScriptUtils {
  /// 显式指定 BOM，避免宿主系统的默认代码页影响生成的脚本。
  static Future<void> write(
    File file,
    String source, {
    required bool withBom,
  }) async {
    await file.writeAsString(
      '${withBom ? '\uFEFF' : ''}$source',
      encoding: utf8,
    );
  }
}
