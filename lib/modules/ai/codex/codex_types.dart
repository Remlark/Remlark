/// Codex 运行环境的公共类型
library;

/// Codex 相关错误（消息已按当前界面语言翻译，可直接显示）
class CodexException implements Exception {
  CodexException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// 安装阶段（界面显示进度文本）
enum CodexInstallStage {
  /// 查询最新版本
  checking,

  /// 下载安装包（有进度）
  downloading,

  /// 解压并校验能否运行
  verifying,
}

/// 已登录的 Codex 账号
class CodexAccount {
  const CodexAccount({required this.type, this.email, this.planType});

  /// 登录方式：chatgpt（ChatGPT 账号）或 apiKey
  final String type;

  /// ChatGPT 账号的邮箱，API Key 登录时为 null
  final String? email;

  /// ChatGPT 订阅类型（plus、pro 等），未知时为 null
  final String? planType;

  /// 从 account/read 返回的 account 字段解析，未登录（null）时返回 null
  static CodexAccount? fromJson(Object? json) {
    if (json is! Map) return null;
    final plan = json['planType']?.toString();
    return CodexAccount(
      type: json['type']?.toString() ?? '',
      email: json['email']?.toString(),
      planType: plan == null || plan == 'unknown' ? null : plan,
    );
  }

  /// 界面展示的订阅名称，例如 plus → Plus、prolite → Pro Lite
  String? get planLabel {
    final plan = planType;
    if (plan == null || plan.isEmpty) return null;
    const known = {'prolite': 'Pro Lite', 'promax': 'Pro Max', 'edu_plus': 'Edu Plus', 'edu_pro': 'Edu Pro'};
    return known[plan] ?? plan[0].toUpperCase() + plan.substring(1).replaceAll('_', ' ');
  }
}

/// Codex 可用模型（来自 app-server 的 model/list）
class CodexModel {
  const CodexModel({
    required this.id,
    required this.displayName,
    this.isDefault = false,
    this.efforts = const [],
    this.defaultEffort,
  });

  /// 模型名称，请求时使用
  final String id;

  /// 显示名称
  final String displayName;

  /// 是否为 Codex 默认模型
  final bool isDefault;

  /// 支持的推理强度，按从低到高排列
  final List<String> efforts;

  /// 默认推理强度，未知时为 null
  final String? defaultEffort;

  /// 从 model/list 的单项解析，缺少模型名时返回 null
  static CodexModel? fromJson(Object? json) {
    if (json is! Map) return null;
    final id = (json['model'] ?? json['id'])?.toString() ?? '';
    if (id.isEmpty) return null;
    final name = json['displayName']?.toString() ?? '';
    final efforts = [
      for (final e in (json['supportedReasoningEfforts'] as List?) ?? const [])
        if (e is Map && e['reasoningEffort'] != null) '${e['reasoningEffort']}',
    ];
    return CodexModel(
      id: id,
      displayName: name.isEmpty ? id : name,
      isDefault: json['isDefault'] == true,
      efforts: efforts,
      defaultEffort: json['defaultReasoningEffort']?.toString(),
    );
  }
}

/// GitHub Releases 中的一个 Codex 版本
class CodexRelease {
  const CodexRelease({required this.version, required this.assetUrl, this.assetSize = 0, this.sha256});

  /// 版本号（不含 rust-v 前缀），例如 0.163.0
  final String version;

  /// 当前平台安装包的下载地址
  final String assetUrl;

  /// 安装包大小（字节），未知时为 0
  final int assetSize;

  /// 安装包的 SHA-256（小写十六进制），发布信息未提供时为 null
  final String? sha256;
}
