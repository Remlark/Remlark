import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;

import '../../../l10n/app_localizations.dart';
import '../../../utils/download_utils.dart';
import '../../../utils/version_utils.dart';
import 'dsh_environment.dart';
import 'dsh_types.dart';

/// dsh 的下载、安装、升级与移除。
///
/// dsh 只以 npm 包发布，因此先下载 Node.js 官方运行时到应用数据目录（SHA-256 校验），
/// 再用这个 Node 自带的 npm 安装 `@deepseek-ai/dsh`。不依赖、也不修改本机已有的 node / npm / dsh。
/// 新版本先装到临时目录并验证可以运行，再整目录替换：失败或中断不会破坏已安装的版本。
class DshInstaller {
  DshInstaller(
    this.env, {
    http.Client? client,
    this.nodeDist = 'https://nodejs.org/dist',
    this.registry = 'https://registry.npmjs.org',
  }) : _client = client ?? http.Client();

  final DshEnvironment env;
  final http.Client _client;

  /// Node.js 发布地址（测试或镜像时替换）
  final String nodeDist;

  /// npm 仓库地址
  final String registry;

  /// 查询接口超时
  static const queryTimeout = Duration(seconds: 20);

  /// npm 安装超时（依赖约 1GB，网络慢时需要较长时间）
  static const npmTimeout = Duration(minutes: 30);

  /// 临时目录前缀（启动安装时清理上次残留）
  static const _stagingPrefix = '.staging-';

  static String _t(String key, [Map<String, Object?> args = const {}]) => S.current.t(key, args);

  /// 查询 npm 上 dsh 的最新版本
  Future<String> latestDshVersion() async {
    final j = await _getJson('$registry/${DshEnvironment.packageName}/latest');
    final v = (j as Map<String, dynamic>)['version'];
    if (v is! String || v.isEmpty) throw DshException(_t('dsh.err.query', {'error': 'version'}));
    return v;
  }

  /// 查询 Node.js 最新的 LTS 版本（index.json 按新到旧排列，lts 字段为代号或 false）
  Future<String> latestNodeVersion() async {
    final list = await _getJson('$nodeDist/index.json');
    for (final item in (list as List)) {
      if (item is Map && item['lts'] is String) return VersionUtils.normalize('${item['version']}');
    }
    throw DshException(_t('dsh.err.query', {'error': 'Node.js LTS'}));
  }

  /// GET JSON
  Future<Object?> _getJson(String url) async {
    try {
      final r = await _client
          .get(Uri.parse(url), headers: const {'Accept': 'application/json', 'User-Agent': 'Remlark'})
          .timeout(queryTimeout);
      if (r.statusCode != 200) throw 'HTTP ${r.statusCode}';
      return jsonDecode(utf8.decode(r.bodyBytes));
    } catch (e) {
      throw DshException(_t('dsh.err.query', {'error': '$e'}));
    }
  }

  /// 已安装的 Node.js 是否需要（重新）安装：未安装，或主版本低于最新 LTS
  bool nodeNeedsInstall(String latestNode) {
    final current = env.nodeVersion;
    if (current == null) return true;
    int major(String v) => int.tryParse(VersionUtils.normalize(v).split('.').first) ?? 0;
    return major(current) < major(latestNode);
  }

  /// 清理上次中断留下的临时目录
  Future<void> cleanStaging() async {
    final root = Directory(env.root);
    if (!await root.exists()) return;
    await for (final e in root.list()) {
      if (p.basename(e.path).startsWith(_stagingPrefix)) {
        try {
          await e.delete(recursive: true);
        } on FileSystemException catch (_) {
          // 占用中的残留下次再清理
        }
      }
    }
  }

  /// 下载并安装 Node.js [version]。[onProgress] 报告已下载与总字节数（总数未知时为 0）
  Future<void> installNode(String version, {void Function(int received, int total)? onProgress}) async {
    final asset = env.platform.nodeAsset(version);
    if (asset == null) throw DshException(_t('dsh.err.unsupported'));
    await Directory(env.root).create(recursive: true);
    final staging = await Directory(env.root).createTemp(_stagingPrefix);
    try {
      final expected = await _nodeChecksum(version, asset);
      final archive = File(p.join(staging.path, asset));
      final String actual;
      try {
        actual = await DownloadUtils.toFile(
          _client,
          '$nodeDist/v$version/$asset',
          archive,
          onProgress: onProgress,
          headers: const {'User-Agent': 'Remlark'},
        );
      } catch (e) {
        throw DshException(_t('dsh.err.download', {'error': '$e'}));
      }
      if (actual != expected) throw DshException(_t('dsh.err.checksum'));

      final out = Directory(p.join(staging.path, 'out'));
      await out.create();
      try {
        await env.platform.extract(archive, out);
      } catch (e) {
        throw DshException(_t('dsh.err.extract', {'error': '$e'}));
      }
      await archive.delete();
      // 安装包只有一个顶层目录 node-v<版本>-<平台>
      final dirs = await out.list().where((e) => e is Directory).toList();
      if (dirs.length != 1) throw DshException(_t('dsh.err.extract', {'error': asset}));
      final nodeDir = dirs.single.path;

      final r = await _run(env.platform.nodeExecutable(nodeDir), const ['--version'], const Duration(seconds: 20));
      if (r.exitCode != 0 || VersionUtils.parseOutput('${r.stdout}') != version) {
        throw DshException(_t('dsh.err.verify', {'error': '${r.stderr}'.trim()}));
      }
      await DshEnvironment.writeNodeVersion(nodeDir, version);
      await _replaceDir(Directory(nodeDir), Directory(env.nodeDir));
    } finally {
      await _deleteQuietly(staging);
    }
  }

  /// 读取官方 SHASUMS256.txt 中 [asset] 的校验值
  Future<String> _nodeChecksum(String version, String asset) async {
    final String text;
    try {
      final r = await _client
          .get(Uri.parse('$nodeDist/v$version/SHASUMS256.txt'), headers: const {'User-Agent': 'Remlark'})
          .timeout(queryTimeout);
      if (r.statusCode != 200) throw 'HTTP ${r.statusCode}';
      text = r.body;
    } catch (e) {
      throw DshException(_t('dsh.err.download', {'error': '$e'}));
    }
    for (final line in const LineSplitter().convert(text)) {
      final parts = line.trim().split(RegExp(r'\s+'));
      if (parts.length == 2 && parts[1] == asset) return parts[0].toLowerCase();
    }
    throw DshException(_t('dsh.err.unsupported'));
  }

  /// 用私有 npm 安装 dsh [version]，验证后替换运行目录，返回安装的版本。
  /// [beforeReplace] 在替换前调用（结束正在运行的 dsh 进程，Windows 下否则无法移动目录）
  Future<String> installDsh(String version, {Future<void> Function()? beforeReplace}) async {
    if (!env.nodeInstalled) throw DshException(_t('dsh.err.verify', {'error': 'node'}));
    final staging = await Directory(env.root).createTemp(_stagingPrefix);
    final cache = p.join(staging.path, '.npm-cache');
    final runtime = p.join(staging.path, 'runtime');
    try {
      await Directory(runtime).create();
      // npm 11 默认跳过依赖的安装脚本，只能在项目 package.json 的 allowScripts 中放行；
      // node-pty 在 Windows 上需要安装脚本放置 conpty（旧版 npm 忽略该字段，照常运行脚本）
      await File(p.join(runtime, 'package.json')).writeAsString(
        jsonEncode({
          'name': 'remlark-dsh-runtime',
          'private': true,
          'allowScripts': {'node-pty': true},
        }),
      );
      final r = await _run(env.nodeExecutable, [
        env.npmCli,
        'install',
        '${DshEnvironment.packageName}@$version',
        '--prefix',
        runtime,
        '--cache',
        cache,
        '--registry',
        registry,
        '--no-audit',
        '--no-fund',
        '--no-update-notifier',
        '--loglevel=error',
      ], npmTimeout);
      if (r.exitCode != 0) throw DshException(_t('dsh.err.npm', {'error': _tail('${r.stderr}')}));

      final installed = await _dshVersionOf(runtime);
      if (installed == null || VersionUtils.compare(installed, version) != 0) {
        throw DshException(_t('dsh.err.verify', {'error': installed ?? 'dsh --version'}));
      }
      await beforeReplace?.call();
      await _replaceDir(Directory(runtime), Directory(env.runtimeDir));
      return installed;
    } finally {
      await _deleteQuietly(staging);
    }
  }

  /// 运行 `dsh --version` 读取 [runtime] 中 dsh 的版本，无法运行返回 null
  Future<String?> _dshVersionOf(String runtime) async {
    try {
      final r = await _run(env.nodeExecutable, [env.dshEntry(runtime), '--version'], const Duration(seconds: 60));
      return r.exitCode == 0 ? VersionUtils.parseOutput('${r.stdout}') : null;
    } catch (_) {
      return null;
    }
  }

  /// 移除 Node.js 与 dsh（保留 DSH_HOME 中的会话记录）
  Future<void> uninstall() async {
    for (final dir in [env.runtimeDir, env.nodeDir]) {
      final d = Directory(dir);
      if (await d.exists()) await d.delete(recursive: true);
    }
  }

  /// 在私有 Node 环境中运行命令，超时则结束进程
  Future<ProcessResult> _run(String exe, List<String> args, Duration timeout) async {
    final process = await Process.start(
      exe,
      args,
      environment: env.processEnvironment(),
      workingDirectory: env.root,
    );
    final out = process.stdout.transform(utf8.decoder).join();
    final err = process.stderr.transform(utf8.decoder).join();
    final int code;
    try {
      code = await process.exitCode.timeout(timeout);
    } on TimeoutException {
      process.kill(ProcessSignal.sigkill);
      throw DshException(_t('dsh.err.timeout'));
    }
    return ProcessResult(process.pid, code, await out, await err);
  }

  /// 错误输出只保留最后几行
  static String _tail(String text) {
    final lines = text.trim().split('\n').where((l) => l.trim().isNotEmpty).toList();
    final tail = lines.skip(lines.length > 6 ? lines.length - 6 : 0).join('\n');
    return tail.length > 800 ? tail.substring(tail.length - 800) : tail;
  }

  /// 整目录替换，失败时恢复旧目录；旧目录删除失败（Windows 下仍被占用）时由下次 [cleanStaging] 清理
  static Future<void> _replaceDir(Directory source, Directory target) async {
    final old = Directory(
      p.join(target.parent.path, '${_stagingPrefix}old-${p.basename(target.path)}-${DateTime.now().microsecondsSinceEpoch}'),
    );
    final hadOld = await target.exists();
    if (hadOld) await target.rename(old.path);
    try {
      await source.rename(target.path);
    } catch (_) {
      if (hadOld) await old.rename(target.path);
      rethrow;
    }
    if (hadOld) await _deleteQuietly(old);
  }

  /// 删除目录，失败时忽略（不覆盖原始异常）
  static Future<void> _deleteQuietly(Directory dir) async {
    try {
      if (await dir.exists()) await dir.delete(recursive: true);
    } on FileSystemException catch (_) {}
  }

  /// 释放网络连接
  void dispose() => _client.close();
}
