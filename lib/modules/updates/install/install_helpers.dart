import 'dart:io';

import 'package:path/path.dart' as p;

import '../../../utils/shell_utils.dart';
import '../update_release.dart';
import 'install_plan.dart';

/// 安装脚本公共机制：命令校验、目录权限探测与 POSIX 提交/回滚。
class InstallHelpers {
  /// 执行准备命令，错误固定化以免泄露系统命令输出。
  static Future<void> run(String command, List<String> arguments) async {
    final r = await Process.run(command, arguments);
    if (r.exitCode != 0) throw const UpdateFailure('updates.error.install');
  }

  /// 以实际写入验证权限；探测失败由平台调用系统授权，而不是执行 sudo 密码读取。
  static Future<bool> writable(String parent) async {
    try {
      final probe = await Directory(parent).createTemp('.remlark-write-');
      await probe.delete();
      return true;
    } catch (_) {
      return false;
    }
  }

  /// 生成带父进程等待和超时的 POSIX 工作脚本，握手发生在授权完成之后。
  static String posixWorker(InstallContext context, String body) {
    final root = ShellUtils.quote(context.directory.path);
    return '''#!/bin/sh
set -eu
cd $root
# 授权完成后通知应用可以安全退出；超时绝不替换仍在运行的应用。
printf ready > ready
count=0
while kill -0 ${context.processId} 2>/dev/null; do
  count=\$((count + 1))
  if [ "\$count" -ge 120 ]; then printf failed > result; exit 1; fi
  sleep 1
done
if [ ! -f commit ] || [ -f abort ]; then printf failed > result; exit 1; fi
$body
''';
  }

  /// 在目标同级目录准备完整副本，提交失败恢复旧目录；保留备份供异常启动恢复。
  static String posixReplace({
    required String source,
    required String target,
    required String copyCommand,
    required String suffix,
  }) {
    final q = ShellUtils.quote;
    final stage = '$target.remlark-new-$suffix';
    final backup = '$target.remlark-backup-$suffix';
    return '''
# 不覆盖上次留下的备份，避免丢失最后一份可恢复版本。
if [ -e ${q(stage)} ] || [ -e ${q(backup)} ]; then printf failed > result; exit 1; fi
rollback() {
  if [ ! -e ${q(target)} ] && [ -e ${q(backup)} ]; then mv ${q(backup)} ${q(target)}; fi
  rm -rf ${q(stage)}
  printf failed > result
}
trap rollback EXIT
$copyCommand ${q(source)} ${q(stage)}
mv ${q(target)} ${q(backup)}
if ! mv ${q(stage)} ${q(target)}; then exit 1; fi
trap - EXIT
printf success > result
''';
  }

  /// 启动非提权监督进程，授权失败时保留当前应用；安装后以原用户启动应用。
  static Future<InstallPlan> posixPlan(
    InstallContext context,
    String worker, {
    required String invocation,
    required String relaunch,
  }) async {
    await File(p.join(context.directory.path, 'worker.sh'))
        .writeAsString(worker);
    final script = File(p.join(context.directory.path, 'launch.sh'));
    await script.writeAsString('''#!/bin/sh
cd ${ShellUtils.quote(context.directory.path)} || exit 1
$invocation
code=\$?
if [ ! -f result ]; then printf failed > result; fi
# 只有主程序确实退出后才重新启动；取消系统授权不会产生第二个实例。
if ! kill -0 ${context.processId} 2>/dev/null; then
  $relaunch
fi
exit "\$code"
''');
    return InstallPlan(
      executable: '/bin/sh',
      arguments: [script.path],
      directory: context.directory,
    );
  }

  /// 应用路径必须是绝对目录且不能等于根目录或用户目录。
  static void validateTarget(String target) {
    if (!p.isAbsolute(target) ||
        p.dirname(target) == target ||
        target == Platform.environment['HOME']) {
      throw const UpdateFailure('updates.error.location');
    }
  }
}
