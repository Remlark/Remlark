import 'dart:async';
import 'dart:convert';
import 'dart:ui' show Offset, Rect;

import 'package:dartssh2/dartssh2.dart';

import '../../../utils/app_log.dart';
import '../../ssh/ssh_exec.dart';

/// Finder 窗口：屏幕上的范围（单位：点）与对应的文件夹
class FinderWindow {
  const FinderWindow(this.bounds, this.path);

  final Rect bounds;
  final String path;
}

/// 远程 Mac 的 Finder 布局：主屏尺寸、桌面目录、按从前到后排列的 Finder 窗口
class FinderLayout {
  const FinderLayout({required this.screenWidth, required this.desktop, required this.windows, this.insertion});

  /// 主屏宽度（点）；与 VNC 帧缓冲宽度（像素）之比即 Retina 缩放
  final double screenWidth;
  final String desktop;
  final List<FinderWindow> windows;

  /// Finder 的插入位置：粘贴时的目标目录（最前 Finder 窗口，桌面处于活动状态时为桌面）
  final String? insertion;

  /// 解析 AppleScript 输出：
  /// 第 1 行“屏宽,屏高”，第 2 行桌面路径，可选一行“@insertion + 制表符 + 插入位置”，
  /// 之后每行“左,上,右,下 + 制表符 + 路径”（窗口从前到后）
  static FinderLayout? parse(String out) {
    final lines = const LineSplitter().convert(out.trim());
    if (lines.length < 2) return null;
    final screen = lines[0].split(',');
    final width = double.tryParse(screen.first.trim());
    if (width == null || width <= 0) return null;
    final windows = <FinderWindow>[];
    String? insertion;
    for (final line in lines.skip(2)) {
      final tab = line.indexOf('\t');
      if (tab < 0) continue;
      if (line.startsWith('@insertion')) {
        insertion = line.substring(tab + 1);
        continue;
      }
      if (line.startsWith('@')) continue; // @count / @error：仅供日志查看
      final b = line.substring(0, tab).split(',').map((e) => double.tryParse(e.trim())).toList();
      if (b.length != 4 || b.contains(null)) continue;
      windows.add(FinderWindow(Rect.fromLTRB(b[0]!, b[1]!, b[2]!, b[3]!), line.substring(tab + 1)));
    }
    return FinderLayout(screenWidth: width, desktop: lines[1], windows: windows, insertion: insertion);
  }

  /// 根据拖放点（VNC 帧缓冲像素坐标）找目标文件夹：
  /// 落在某个 Finder 窗口内取最前面的那个窗口，否则为桌面；
  /// [point] 为空（如通过按钮选择文件）时取最前面的 Finder 窗口，没有窗口则为桌面
  String folderAt(Offset? point, int framebufferWidth) {
    if (point == null) return windows.isNotEmpty ? windows.first.path : desktop;
    // 帧缓冲为像素，Finder 坐标为点，Retina 屏需要换算
    final scale = framebufferWidth > 0 ? framebufferWidth / screenWidth : 1.0;
    final p = point / scale;
    for (final w in windows) {
      if (w.bounds.contains(p)) return w.path;
    }
    return desktop;
  }
}

/// 无法确定远程目标文件夹（[code] 为多语言 key，[detail] 为原始错误）
class FinderLocateException implements Exception {
  FinderLocateException(this.code, this.detail);

  final String code;
  final String? detail;

  @override
  String toString() => detail == null ? code : '$code: $detail';
}

/// Finder 查询结果：成功时 [layout] 非空；失败时 [error] 为错误码（多语言 key），[detail] 为原始输出
class FinderQueryResult {
  const FinderQueryResult.ok(FinderLayout this.layout) : error = null, detail = null;
  const FinderQueryResult.fail(String this.error, [this.detail]) : layout = null;

  final FinderLayout? layout;

  /// finder.not_mac：远程不是 macOS；finder.denied：未授权控制 Finder；
  /// finder.timeout：等待授权或执行超时；finder.failed：其他错误
  final String? error;
  final String? detail;
}

/// 在远程 Mac 上查询 Finder 窗口布局，用于确定拖放上传的目标文件夹。
///
/// SSH 会话中的进程不在图形会话里，直接 osascript 控制 Finder 会被系统立即拒绝（-1743），
/// 且无法弹出授权提示。因此在远程 Mac 上用 osacompile 编译一个辅助小程序（RemlarkFinder），
/// 通过 `open -g` 在图形会话中后台运行：首次运行时远程屏幕会弹出“允许控制 Finder”的提示，
/// 点击“好”后永久生效；小程序把结果写入文件，再经 SSH 读取。
class FinderLocator {
  FinderLocator._();

  /// 查询超时：首次使用时需要等待远程用户点击授权
  static const timeout = Duration(seconds: 20);

  /// 辅助小程序名称（脚本内容变化时递增版本号，使远程重新编译）
  static const appName = 'RemlarkFinder-4';

  /// 小程序脚本：查询 Finder 布局，写入结果文件；出错时写入“ERROR:错误号:信息”
  static const _applet = '''
set outPath to (POSIX path of (path to home folder)) & "Library/Application Support/Remlark/finder-layout.txt"
try
  -- 每个发给 Finder 的请求最多等 5 秒（Finder 无响应时放弃，不会一直挂起）
  with timeout of 5 seconds
  tell application "Finder"
    set b to bounds of window of desktop
    set out to ((item 3 of b) as text) & "," & ((item 4 of b) as text) & linefeed
    set out to out & (POSIX path of (path to desktop folder)) & linefeed
    try
      set out to out & "@insertion" & tab & (POSIX path of (insertion location as alias)) & linefeed
    end try
    set n to count of Finder windows
    set out to out & "@count" & tab & n & linefeed
    repeat with i from 1 to n
      -- 每个属性单独容错：失败时输出 @error 行（写入日志便于定位），不影响其他窗口
      try
        set w to Finder window i
        set wb to bounds of w
        set p to POSIX path of (target of w as alias)
        set out to out & (item 1 of wb) & "," & (item 2 of wb) & "," & (item 3 of wb) & "," & (item 4 of wb) & tab & p & linefeed
      on error errMsg number errNum
        set out to out & "@error" & tab & "window " & i & ": " & errNum & " " & errMsg & linefeed
      end try
    end repeat
  end tell
  end timeout
on error errMsg number errNum
  set out to "ERROR:" & errNum & ":" & errMsg
end try
set f to open for access (POSIX file outPath) with write permission
set eof f to 0
write out to f as «class utf8»
close access f
''';

  /// 远程执行的 shell：首次编译小程序，在图形会话中后台运行并等待结束，输出结果文件
  static String _shell(String appletName, String applet) =>
      '''
command -v osacompile >/dev/null 2>&1 || { echo "__NOT_MAC__"; exit 0; }
D="\$HOME/Library/Application Support/Remlark"
APP="\$D/$appletName.app"
OUT="\$D/finder-layout.txt"
mkdir -p "\$D"
if [ ! -d "\$APP" ]; then
rm -rf "\$D"/RemlarkFinder-*.app "\$D"/RemlarkFinder-*.applescript
cat > "\$D/$appletName.applescript" <<'REMLARK_EOF'
$applet
REMLARK_EOF
osacompile -o "\$APP" "\$D/$appletName.applescript" || { echo "__COMPILE_FAILED__"; exit 0; }
fi
rm -f "\$OUT"
# 结束可能残留的旧实例（已运行的小程序再次 open 只会被激活而不会重新执行）
pkill -f "Remlark/RemlarkFinder-" 2>/dev/null
open -g "\$APP" || { echo "__OPEN_FAILED__"; exit 0; }
# 最多等待 10 秒结果；超时则强制结束小程序，避免其一直挂起
i=0
while [ ! -s "\$OUT" ] && [ \$i -lt 100 ]; do sleep 0.1; i=\$((i+1)); done
if [ ! -s "\$OUT" ]; then pkill -f "Remlark/RemlarkFinder-" 2>/dev/null; echo "__TIMEOUT__"; exit 0; fi
sleep 0.1
cat "\$OUT" 2>/dev/null
''';

  /// 查询 Finder 布局。[appletName] / [applet] 仅供测试替换
  static Future<FinderQueryResult> query(
    SSHClient client, {
    String appletName = appName,
    String applet = _applet,
  }) async {
    final String out;
    try {
      out = (await SshExec.run(client, '/bin/sh -s', stdin: _shell(appletName, applet), timeout: timeout)).stdout;
    } on TimeoutException {
      AppLog.w('finder', '查询超时，可能在等待远程用户授权');
      return const FinderQueryResult.fail('finder.timeout');
    } catch (e, st) {
      AppLog.e('finder', '执行失败', e, st);
      return FinderQueryResult.fail('finder.failed', '$e');
    }
    final text = out.trim();
    if (text.contains('__NOT_MAC__')) return const FinderQueryResult.fail('finder.not_mac');
    if (text.contains('__TIMEOUT__')) {
      AppLog.w('finder', '辅助小程序 10 秒内未返回结果（等待授权或 Finder 无响应），已强制结束');
      return const FinderQueryResult.fail('finder.timeout');
    }
    if (text.startsWith('ERROR:')) {
      // -1743：未授权发送 Apple 事件（曾点过“不允许”）
      final denied = text.startsWith('ERROR:-1743') || text.startsWith('ERROR:-1744');
      return FinderQueryResult.fail(denied ? 'finder.denied' : 'finder.failed', text);
    }
    final layout = FinderLayout.parse(text);
    if (layout == null) return FinderQueryResult.fail('finder.failed', text);
    return FinderQueryResult.ok(layout);
  }
}
