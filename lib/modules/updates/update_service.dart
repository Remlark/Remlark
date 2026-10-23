import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import '../../utils/download_utils.dart';
import 'github_release_client.dart';
import 'update_release.dart';

/// 更新网络服务负责查询及校验下载，安装由独立平台助手接管。
class UpdateService {
  UpdateService({GithubReleaseClient? client})
    : client = client ?? GithubReleaseClient();
  final GithubReleaseClient client;

  /// 查询最新正式 Release，私有仓库无权限与尚未发布均给出可操作提示。
  Future<UpdateRelease> latest() async {
    final response = await client
        .get(Uri.parse('${GithubReleaseClient.apiRoot}latest'))
        .timeout(const Duration(seconds: 55));
    if (response.statusCode != 200) {
      throw UpdateFailure(_error(response.statusCode));
    }
    try {
      return UpdateRelease.fromJson(
        jsonDecode(response.body) as Map<String, dynamic>,
      );
    } on UpdateFailure {
      rethrow;
    } catch (_) {
      throw const UpdateFailure('updates.error.release');
    }
  }

  /// 将 HTTP 状态映射为固定文案，不把响应正文、Token 或签名 URL 写入日志/UI。
  String _error(int status) => switch (status) {
    401 => 'updates.error.token',
    403 || 429 => 'updates.error.forbidden',
    404 => 'updates.error.not_found',
    _ => 'updates.error.network',
  };

  /// 下载到目标目录的临时子目录，校验成功后才交付最终文件；失败保留原文件。
  Future<void> download(
    UpdateRelease release,
    UpdateAsset asset,
    String destination,
    void Function(int, int) onProgress,
  ) async {
    final folder = await Directory(p.dirname(destination))
        .createTemp('.remlark-update-');
    try {
      var expected = asset.digest;
      if (expected == null ||
          !RegExp(r'^sha256:[a-fA-F0-9]{64}$').hasMatch(expected)) {
        final sums = release.asset('SHA256SUMS');
        if (sums == null || sums.size > 1024 * 1024) {
          throw const UpdateFailure('updates.error.checksum');
        }
        final response = await client
            .get(
              Uri.parse('${GithubReleaseClient.apiRoot}assets/${sums.id}'),
              headers: {'Accept': 'application/octet-stream'},
            )
            .timeout(const Duration(seconds: 55));
        if (response.statusCode != 200) {
          throw UpdateFailure(_error(response.statusCode));
        }
        final entries = const LineSplitter()
            .convert(response.body)
            .where((line) => line.endsWith('  ${asset.name}'))
            .toList();
        if (entries.length != 1 ||
            !RegExp(r'^[a-fA-F0-9]{64}  ').hasMatch(entries.single)) {
          throw const UpdateFailure('updates.error.checksum');
        }
        expected = 'sha256:${entries.single.substring(0, 64)}';
      }
      final file = File(p.join(folder.path, 'payload'));
      final actual = await DownloadUtils.toFile(
        client,
        '${GithubReleaseClient.apiRoot}assets/${asset.id}',
        file,
        headers: {'Accept': 'application/octet-stream'},
        onProgress: onProgress,
      );
      if ('sha256:$actual' != expected.toLowerCase() ||
          await file.length() != asset.size) {
        throw const UpdateFailure('updates.error.checksum');
      }
      // 只交付校验通过的暂存文件，随后交给平台安装助手。
      await file.rename(destination);
    } finally {
      if (await folder.exists()) await folder.delete(recursive: true);
    }
  }

  /// 关闭 HTTP 连接。
  void close() => client.close();
}
