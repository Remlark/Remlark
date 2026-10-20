import 'dart:async';
import 'dart:convert';

import 'package:dartssh2/dartssh2.dart';

import '../../../utils/app_log.dart';
import '../../../utils/shell_utils.dart';
import '../../ssh/ssh_exec.dart';

/// 远程剪贴板内容
class RemotePasteboard {
  const RemotePasteboard({required this.changeCount, required this.files, this.text});

  /// NSPasteboard 变化计数：每次复制递增，用于判断是否有新内容
  final int changeCount;

  /// 复制的文件（绝对路径），非文件时为空
  final List<String> files;
  final String? text;
}

/// 经 SSH 读写远程 macOS 剪贴板（文本与文件），并查询远程最前面的应用。
///
/// macOS 自带的屏幕共享服务端不处理第三方客户端发送的标准 RFB 剪贴板消息（ClientCutText），
/// 且 RFB 标准剪贴板只支持 Latin-1、不支持文件；剪贴板不受隐私权限限制，SSH 会话可直接访问：
/// 文本用 pbcopy / pbpaste，文件用 JXA（osascript -l JavaScript）读写 NSPasteboard 的文件 URL。
class SshClipboard {
  SshClipboard._();

  static const _timeout = Duration(seconds: 10);

  /// 让 pbcopy / pbpaste 按 UTF-8 处理文本
  static const _utf8 = 'LANG=en_US.UTF-8 LC_ALL=en_US.UTF-8';

  /// 写入剪贴板并用 pbpaste 回读核对；远程没有 pbcopy（非 macOS）返回 false
  static Future<bool> write(SSHClient client, String text) async {
    try {
      final r = await SshExec.run(client, '$_utf8 pbcopy', stdin: text, timeout: _timeout);
      if (!r.ok) {
        AppLog.w('clipboard', 'SSH pbcopy 失败 exit=${r.exitCode} ${r.stderr.trim()}');
        return false;
      }
      // 回读核对，确认写入的是图形会话的剪贴板
      final back = (await SshExec.run(client, '$_utf8 pbpaste', timeout: _timeout)).stdout;
      return back == text;
    } catch (e, st) {
      AppLog.e('clipboard', 'SSH 写入远程剪贴板异常', e, st);
      return false;
    }
  }

  /// 读取剪贴板：变化计数、文件路径、文本（JSON 输出）
  static const _readJs = r'''
ObjC.import("AppKit");
var pb = $.NSPasteboard.generalPasteboard;
var files = [];
var urls = pb.readObjectsForClassesOptions($([$.NSURL]), $({"NSPasteboardURLReadingFileURLsOnlyKey": true}));
if (urls) for (var i = 0; i < urls.count; i++) files.push(ObjC.unwrap(urls.objectAtIndex(i).path));
var text = files.length ? null : ObjC.unwrap(pb.stringForType($.NSPasteboardTypeString));
JSON.stringify({changeCount: Number(pb.changeCount), files: files, text: text === undefined ? null : text});
''';

  /// 写入文件 URL 到剪贴板，输出新的变化计数与回读的文件数
  static const _writeFilesJs = r'''
ObjC.import("AppKit");
function run(argv) {
  var pb = $.NSPasteboard.generalPasteboard;
  pb.clearContents;
  var arr = $.NSMutableArray.alloc.init;
  for (var i = 0; i < argv.length; i++) arr.addObject($.NSURL.fileURLWithPath(argv[i]));
  var ok = pb.writeObjects(arr);
  var back = pb.readObjectsForClassesOptions($([$.NSURL]), $({}));
  return JSON.stringify({ok: ok, changeCount: Number(pb.changeCount), count: back ? Number(back.count) : 0});
}
''';

  /// 读取远程剪贴板；失败返回 null
  static Future<RemotePasteboard?> read(SSHClient client) async {
    try {
      final r = await SshExec.run(client, 'osascript -l JavaScript -', stdin: _readJs, timeout: _timeout);
      if (!r.ok) {
        AppLog.w('clipboard', '读取远程剪贴板失败 exit=${r.exitCode} ${r.stderr.trim()}');
        return null;
      }
      final m = jsonDecode(r.stdout.trim()) as Map<String, dynamic>;
      return RemotePasteboard(
        changeCount: _int(m['changeCount']),
        files: [for (final f in m['files'] as List) f as String],
        text: m['text'] as String?,
      );
    } catch (e, st) {
      AppLog.e('clipboard', '读取远程剪贴板异常', e, st);
      return null;
    }
  }

  /// 把远程文件写入远程剪贴板（效果同在远程 Finder 中拷贝），返回新的变化计数；失败返回 null
  static Future<int?> writeFiles(SSHClient client, List<String> remotePaths) async {
    try {
      final args = remotePaths.map(ShellUtils.quote).join(' ');
      final r = await SshExec.run(client, 'osascript -l JavaScript - $args', stdin: _writeFilesJs, timeout: _timeout);
      if (!r.ok) {
        AppLog.w('clipboard', '写入远程文件剪贴板失败 exit=${r.exitCode} ${r.stderr.trim()}');
        return null;
      }
      final m = jsonDecode(r.stdout.trim()) as Map<String, dynamic>;
      return (m['ok'] == true || m['ok'] == 'true') ? _int(m['changeCount']) : null;
    } catch (e, st) {
      AppLog.e('clipboard', '写入远程文件剪贴板异常', e, st);
      return null;
    }
  }

  /// 远程最前面应用的 bundle id（如 com.apple.finder）；失败返回 null
  static Future<String?> frontApp(SSHClient client) async {
    try {
      final r = await SshExec.run(client, r'lsappinfo info -only bundleid "$(lsappinfo front)"', timeout: _timeout);
      final m = RegExp(r'"CFBundleIdentifier"="([^"]*)"').firstMatch(r.stdout);
      return m?.group(1);
    } catch (e, st) {
      AppLog.e('clipboard', '查询远程最前面的应用异常', e, st);
      return null;
    }
  }

  /// JXA 输出的数字可能是字符串，统一转为整数
  static int _int(Object? v) => v is num ? v.toInt() : int.parse('$v');
}
