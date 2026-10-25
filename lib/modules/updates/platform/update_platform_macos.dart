import 'dart:ffi';
import 'dart:io';

import 'package:path/path.dart' as p;

import '../../../utils/shell_utils.dart';
import '../install/install_helpers.dart';
import '../install/install_plan.dart';
import '../update_release.dart';
import 'update_platform.dart';

/// macOS 使用保留签名的通用 zip，退出后原位替换完整 App。
class MacosUpdatePlatform implements UpdatePlatform {
  MacosUpdatePlatform(this.abi);
  final Abi abi;

  /// 使用发布工作流生成的通用应用归档，无需挂载 DMG。
  @override
  String? assetName(String version) =>
      [Abi.macosX64, Abi.macosArm64].contains(abi) ? 'Remlark-macos.zip' : null;

  /// 检查应用结构、签名和内嵌版本，再生成可按需请求系统授权的安装助手。
  @override
  Future<InstallPlan> prepare(InstallContext context) async {
    final target = p.dirname(p.dirname(p.dirname(context.executable)));
    if (!target.endsWith('.app') ||
        !context.executable.endsWith('/Contents/MacOS/Remlark') ||
        target.contains('/AppTranslocation/') ||
        target.startsWith('/Volumes/')) {
      throw const UpdateFailure('updates.error.location');
    }
    InstallHelpers.validateTarget(target);
    final extracted = await Directory(
      p.join(context.directory.path, 'extracted'),
    ).create();
    await InstallHelpers.run('/usr/bin/ditto', [
      '-x',
      '-k',
      context.archive.path,
      extracted.path,
    ]);
    final source = p.join(extracted.path, 'Remlark.app');
    await InstallHelpers.run('/usr/bin/codesign', [
      '--verify',
      '--deep',
      '--strict',
      source,
    ]);
    final version = await Process.run('/usr/bin/plutil', [
      '-extract',
      'CFBundleShortVersionString',
      'raw',
      '-o',
      '-',
      p.join(source, 'Contents/Info.plist'),
    ]);
    if (version.exitCode != 0 ||
        '${version.stdout}'.trim() != context.version ||
        !File(p.join(source, 'Contents/MacOS/Remlark')).existsSync()) {
      throw const UpdateFailure('updates.error.install');
    }
    final suffix = p.basename(context.directory.path);
    await File(p.join(context.directory.path, 'backup'))
        .writeAsString('$target.remlark-backup-$suffix');
    final worker = InstallHelpers.posixWorker(
      context,
      InstallHelpers.posixReplace(
        source: source,
        target: target,
        copyCommand: '/usr/bin/ditto',
        suffix: suffix,
      ),
    );
    final command =
        '/bin/sh ${ShellUtils.quote(p.join(context.directory.path, 'worker.sh'))}';
    var invocation = command;
    if (!await InstallHelpers.writable(p.dirname(target))) {
      // AppleScript 字符串与 shell 参数分开转义，用户路径永远不作为代码拼接。
      final literal = command.replaceAll('\\', '\\\\').replaceAll('"', '\\"');
      final authorization = File(
        p.join(context.directory.path, 'authorize.applescript'),
      );
      await authorization.writeAsString(
        'do shell script "$literal" with administrator privileges',
      );
      invocation = '/usr/bin/osascript ${ShellUtils.quote(authorization.path)}';
    }
    return InstallHelpers.posixPlan(
      context,
      worker,
      invocation: invocation,
      relaunch: '/usr/bin/open ${ShellUtils.quote(target)}',
    );
  }
}
