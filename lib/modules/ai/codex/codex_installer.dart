import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;

import '../../../l10n/app_localizations.dart';
import '../../../utils/archive/archive_extractor.dart';
import '../../../utils/download_utils.dart';
import '../../../utils/version_utils.dart';
import 'codex_environment.dart';
import 'codex_types.dart';

/// Codex 的下载、安装、升级与移除：从 GitHub Releases 下载当前平台的完整运行包，解压到应用数据目录。
/// 不依赖 npm、Homebrew 等包管理器，也不影响用户自行安装的 codex。
/// 新版本先解压到临时目录并验证可以运行，再整目录替换：失败或中断不会破坏已安装的版本。
class CodexInstaller {
  CodexInstaller(
    this.env, {
    http.Client? client,
    this.latestReleaseUrl = 'https://api.github.com/repos/openai/codex/releases/latest',
    ArchiveExtractor? extractor,
  }) : _client = client ?? http.Client(),
       _extractor = extractor ?? ArchiveExtractor.current();

  final CodexEnvironment env;
  final http.Client _client;
  final ArchiveExtractor _extractor;

  /// 最新版本的查询地址（测试时替换为本地服务）
  final String latestReleaseUrl;

  /// 查询接口超时
  static const queryTimeout = Duration(seconds: 20);

  /// 临时目录前缀（启动安装时清理上次残留）
  static const _stagingPrefix = '.staging-';

  static String _t(String key, [Map<String, Object?> args = const {}]) => S.current.t(key, args);

  /// 查询最新版本及当前平台安装包的下载地址与校验值
  Future<CodexRelease> latestRelease() async {
    final asset = env.platform.releaseAsset;
    if (asset == null) throw CodexException(_t('codex.err.unsupported'));
    final Map<String, dynamic> json;
    try {
      final r = await _client
          .get(
            Uri.parse(latestReleaseUrl),
            headers: const {'Accept': 'application/vnd.github+json', 'User-Agent': 'Remlark'},
          )
          .timeout(queryTimeout);
      if (r.statusCode != 200) throw 'HTTP ${r.statusCode}';
      json = jsonDecode(utf8.decode(r.bodyBytes)) as Map<String, dynamic>;
    } catch (e) {
      throw CodexException(_t('codex.err.query', {'error': '$e'}));
    }
    final version = VersionUtils.normalize('${json['tag_name'] ?? ''}'.replaceFirst('rust-', ''));
    for (final item in (json['assets'] as List?) ?? const []) {
      if (item is Map && item['name'] == asset) {
        final digest = '${item['digest'] ?? ''}';
        return CodexRelease(
          version: version,
          assetUrl: '${item['browser_download_url'] ?? ''}',
          assetSize: (item['size'] as num?)?.toInt() ?? 0,
          sha256: digest.startsWith('sha256:') ? digest.substring(7).toLowerCase() : null,
        );
      }
    }
    throw CodexException(_t('codex.err.unsupported'));
  }

  /// 清理上次中断留下的临时目录
  Future<void> cleanStaging() async {
    final root = Directory(env.root);
    if (!await root.exists()) return;
    await for (final e in root.list()) {
      if (p.basename(e.path).startsWith(_stagingPrefix)) await _deleteQuietly(e);
    }
  }

  /// 下载并安装 [release]，返回安装后的版本号。[onProgress] 报告已下载与总字节数（总数未知时为 0）；
  /// [onVerifying] 在下载完成、开始解压校验时调用；[beforeReplace] 在替换前调用（结束正在运行的 Codex，
  /// Windows 下否则无法移动目录）
  Future<String> install(
    CodexRelease release, {
    void Function(int received, int total)? onProgress,
    void Function()? onVerifying,
    Future<void> Function()? beforeReplace,
  }) async {
    await Directory(env.root).create(recursive: true);
    final staging = await Directory(env.root).createTemp(_stagingPrefix);
    try {
      final archive = File(p.join(staging.path, 'codex.tar.gz'));
      final String actual;
      try {
        actual = await DownloadUtils.toFile(
          _client,
          release.assetUrl,
          archive,
          onProgress: onProgress,
          headers: const {'User-Agent': 'Remlark'},
        );
      } catch (e) {
        throw CodexException(_t('codex.err.download', {'error': '$e'}));
      }
      if (release.sha256 != null && actual != release.sha256) throw CodexException(_t('codex.err.checksum'));
      onVerifying?.call();

      final runtime = Directory(p.join(staging.path, 'runtime'));
      await runtime.create();
      try {
        await _extractor.extract(archive, runtime);
      } catch (e) {
        throw CodexException(_t('codex.err.extract', {'error': '$e'}));
      }
      await archive.delete();
      await _verify(runtime.path, release.version);
      await beforeReplace?.call();
      await _replaceDir(runtime, Directory(env.runtimeDir));
      return release.version;
    } finally {
      await _deleteQuietly(staging);
    }
  }

  /// 校验解压出的运行包：主程序与执行工具都能运行，版本与发布信息一致
  Future<void> _verify(String runtime, String version) async {
    final exe = env.executableIn(runtime);
    final host = env.codeModeHostIn(runtime);
    if (!File(exe).existsSync() || !File(host).existsSync()) {
      throw CodexException(_t('codex.err.verify', {'error': 'bin/${env.platform.executableName}'}));
    }
    final r = await _run(exe, const ['--version']);
    final installed = r.exitCode == 0 ? VersionUtils.parseOutput('${r.stdout}') : null;
    if (installed == null || VersionUtils.compare(installed, version) != 0) {
      throw CodexException(_t('codex.err.verify', {'error': installed ?? '${r.stderr}'.trim()}));
    }
    // --version 只验证主程序；单独启动执行工具，提前发现权限和动态库问题
    final h = await _run(host, const ['--help']);
    if (h.exitCode != 0) throw CodexException(_t('codex.err.verify', {'error': env.platform.codeModeHostName}));
  }

  /// 运行命令，超时视为失败
  static Future<ProcessResult> _run(String exe, List<String> args) async {
    try {
      return await Process.run(exe, args).timeout(const Duration(seconds: 30));
    } catch (e) {
      return ProcessResult(0, -1, '', '$e');
    }
  }

  /// 移除运行包（保留各 Agent 的 CODEX_HOME，即登录状态与会话记录）
  Future<void> uninstall() async {
    final d = Directory(env.runtimeDir);
    if (await d.exists()) await d.delete(recursive: true);
  }

  /// 整目录替换，失败时恢复旧目录；旧目录删除失败（Windows 下仍被占用）时由下次 [cleanStaging] 清理
  static Future<void> _replaceDir(Directory source, Directory target) async {
    final old = Directory(
      p.join(
        target.parent.path,
        '${_stagingPrefix}old-${p.basename(target.path)}-${DateTime.now().microsecondsSinceEpoch}',
      ),
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

  /// 删除文件或目录，失败时忽略（不覆盖原始异常）
  static Future<void> _deleteQuietly(FileSystemEntity e) async {
    try {
      if (await e.exists()) await e.delete(recursive: true);
    } on FileSystemException catch (_) {}
  }

  /// 释放网络连接
  void dispose() => _client.close();
}
