import 'dart:io';

/// 读取受版本控制的文本文件并统一为 LF 换行。
/// Windows 上 git 默认 autocrlf 检出为 CRLF，断言中包含 `\n` 的片段需先归一化才能三平台一致。
String readSourceText(String path) =>
    File(path).readAsStringSync().replaceAll('\r\n', '\n');
