import 'dart:ffi';
import 'dart:io';

import 'package:path/path.dart' as p;

import '../../../utils/platform_utils.dart';
import '../../../utils/shell_utils.dart';
import '../install/install_helpers.dart';
import '../install/install_plan.dart';
import '../update_release.dart';
import 'update_platform.dart';

/// Linux：系统 deb 安装保持包管理，便携安装原位替换 bundle。
class LinuxUpdatePlatform implements UpdatePlatform {
  LinuxUpdatePlatform(this.abi, {this.executable = ''});
  final Abi abi;
  final String executable;
  bool get deb => p.dirname(executable) == '/opt/remlark';

  /// 根据实际安装类型选择附件，不向非 Debian 便携安装推送 deb。
  @override
  String? assetName(String version) => switch (abi) {
    Abi.linuxX64 =>
      deb ? 'Remlark-$version-linux-amd64.deb' : 'Remlark-linux-x64.tar.gz',
    Abi.linuxArm64 =>
      deb ? 'Remlark-$version-linux-arm64.deb' : 'Remlark-linux-arm64.tar.gz',
    _ => null,
  };

  /// 校验包或解压结果；系统目录通过 polkit 获取授权，重启仍使用原用户。
  @override
  Future<InstallPlan> prepare(InstallContext context) async {
    final target = p.dirname(context.executable);
    InstallHelpers.validateTarget(target);
    if (p.basename(context.executable) != 'Remlark') {
      throw const UpdateFailure('updates.error.location');
    }
    final q = ShellUtils.quote;
    String body;
    bool elevate;
    if (deb) {
      // 确认系统目录确实由 remlark 包管理，拒绝仅凭同名路径覆盖未知文件。
      final owner = await Process.run('dpkg-query', ['-S', context.executable]);
      final version = await Process.run('dpkg-deb', [
        '-f',
        context.archive.path,
        'Package',
        'Version',
      ]);
      if (owner.exitCode != 0 ||
          !'${owner.stdout}'.startsWith('remlark:') ||
          version.exitCode != 0 ||
          !'${version.stdout}'.contains('Package: remlark') ||
          !'${version.stdout}'.contains('Version: ${context.version}\n')) {
        throw const UpdateFailure('updates.error.install');
      }
      body =
          'if /usr/bin/dpkg -i ${q(context.archive.path)}; then printf success > result; else printf failed > result; exit 1; fi';
      elevate = true;
    } else {
      if (!Directory(p.join(target, 'lib')).existsSync() ||
          !Directory(p.join(target, 'data')).existsSync()) {
        throw const UpdateFailure('updates.error.location');
      }
      final extracted = await Directory(
        p.join(context.directory.path, 'extracted'),
      ).create();
      await InstallHelpers.run('tar', [
        '-xzf',
        context.archive.path,
        '-C',
        extracted.path,
      ]);
      final source = p.join(extracted.path, 'bundle');
      if (!File(p.join(source, 'Remlark')).existsSync() ||
          !Directory(p.join(source, 'lib')).existsSync() ||
          !Directory(p.join(source, 'data')).existsSync()) {
        throw const UpdateFailure('updates.error.install');
      }
      final suffix = p.basename(context.directory.path);
      await File(p.join(context.directory.path, 'backup'))
          .writeAsString('$target.remlark-backup-$suffix');
      body = InstallHelpers.posixReplace(
        source: source,
        target: target,
        copyCommand: '/bin/cp -a',
        suffix: suffix,
      );
      elevate = !await InstallHelpers.writable(p.dirname(target));
    }
    final helper = q(p.join(context.directory.path, 'worker.sh'));
    final pkexec = elevate ? PlatformUtils.which('pkexec') : null;
    if (elevate && pkexec == null) {
      throw const UpdateFailure('updates.error.permission');
    }
    return InstallHelpers.posixPlan(
      context,
      InstallHelpers.posixWorker(context, body),
      invocation: elevate ? '${q(pkexec!)} /bin/sh $helper' : '/bin/sh $helper',
      relaunch: 'cd ${q(target)} && nohup ${q(context.executable)} >/dev/null 2>&1 &',
    );
  }
}
