import '../../utils/version_utils.dart';

/// 发布元数据无效时拒绝当作可安装的新版本。
class UpdateFailure implements Exception {
  const UpdateFailure(this.key);
  final String key;
}

/// GitHub 发布附件；下载地址由固定仓库与附件 ID 构造，不信任响应中的 URL。
class UpdateAsset {
  const UpdateAsset(this.id, this.name, this.size, this.digest);
  final int id;
  final String name;
  final int size;
  final String? digest;

  /// 解析附件并保留 GitHub 提供的摘要。
  factory UpdateAsset.fromJson(Map<String, dynamic> json) => UpdateAsset(
    json['id'] as int,
    json['name'] as String,
    json['size'] as int,
    json['digest'] as String?,
  );
}

/// 只接受正式发布和严格的版本标签；开发构建不声称已经是最新版。
class UpdateRelease {
  const UpdateRelease(this.version, this.notes, this.assets);
  final String version;
  final String notes;
  final List<UpdateAsset> assets;

  /// 检验来自 GitHub 的版本与附件元数据。
  factory UpdateRelease.fromJson(Map<String, dynamic> json) {
    final tag = json['tag_name'] as String? ?? '';
    if (json['draft'] != false ||
        json['prerelease'] != false ||
        !RegExp(r'^v?(0|[1-9]\d*)\.(0|[1-9]\d*)\.(0|[1-9]\d*)$')
            .hasMatch(tag)) {
      throw const UpdateFailure('updates.error.release');
    }
    final assets = (json['assets'] as List)
        .map((v) => UpdateAsset.fromJson(Map<String, dynamic>.from(v as Map)))
        .toList();
    if (assets.any((a) => a.id <= 0 || a.size < 0)) {
      throw const UpdateFailure('updates.error.release');
    }
    return UpdateRelease(
      tag.replaceFirst(RegExp(r'^v'), ''),
      json['body'] as String? ?? '',
      assets,
    );
  }

  /// 查找唯一的附件，重复名称也视为不完整发布。
  UpdateAsset? asset(String? name) {
    final matches = assets.where((a) => a.name == name).toList();
    return matches.length == 1 ? matches.single : null;
  }

  /// 构建元数据不影响版本优先级，开发版本需要用户自行核对。
  bool newerThan(String current) =>
      current != 'development' && VersionUtils.compare(version, current) > 0;
}
