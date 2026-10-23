import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../platform_utils.dart';

/// 复用 Git 的 HTTPS 凭据助手；不读取 SSH 私钥、不保存凭据、不触发登录流程。
class GitCredentials {
  GitCredentials({this.workingDirectory, this.environment = const {}});
  final String? workingDirectory;
  final Map<String, String> environment;

  /// 通过 Git 自己的配置解析系统、全局和当前仓库凭据，只查询指定仓库。
  Future<String?> githubToken() async {
    final git = PlatformUtils.which('git');
    if (git == null) return null;
    Process? process;
    try {
      process = await Process.start(
        git,
        [
          '-c',
          'credential.interactive=false',
          '-c',
          'core.askPass=',
          'credential',
          'fill',
        ],
        workingDirectory: workingDirectory,
        environment: {
          ...environment,
          'GIT_TERMINAL_PROMPT': '0',
          'GCM_INTERACTIVE': 'never',
          'GIT_ASKPASS': '',
          'SSH_ASKPASS': '',
        },
      );
      // 输出只在内存中解析，不能经 AppLog、异常或 UI 暴露。
      final output = process.stdout.transform(utf8.decoder).join();
      final errors = process.stderr.drain<void>();
      process.stdin.write(
        'protocol=https\nhost=github.com\npath=Remlark/Remlark.git\n\n',
      );
      await process.stdin.close();
      final code = await process.exitCode.timeout(const Duration(seconds: 10));
      await errors;
      if (code != 0) return null;
      return parse(await output);
    } catch (_) {
      process?.kill();
      return null;
    }
  }

  /// 只接受 GitHub HTTPS 凭据，拒绝换行注入及其他主机的返回值。
  static String? parse(String output) {
    final fields = <String, String>{};
    for (final line in const LineSplitter().convert(output)) {
      final index = line.indexOf('=');
      if (index > 0) {
        fields[line.substring(0, index)] = line.substring(index + 1);
      }
    }
    if (fields['protocol'] != 'https' || fields['host'] != 'github.com') {
      return null;
    }
    final token = fields['password'];
    return token == null || token.isEmpty || token.contains(RegExp(r'[\s\x00]'))
        ? null
        : token;
  }
}
