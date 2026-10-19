/// 同步配置
class SyncConfig {
  const SyncConfig({
    this.serverUrl = '',
    this.token = '',
    this.passphrase = '',
    this.intervalMinutes = 0,
    this.lastSyncAt,
  });

  /// 同步服务器地址，例如 https://sync.example.com:8443
  final String serverUrl;

  /// 访问令牌（服务器按令牌划分数据空间）
  final String token;

  /// 端到端加密口令（只保存在客户端，服务器无法解密）
  final String passphrase;

  /// 自动同步间隔（分钟），0 表示关闭自动同步
  final int intervalMinutes;
  final int? lastSyncAt;

  /// 是否已配置
  bool get isConfigured => serverUrl.trim().isNotEmpty && token.isNotEmpty && passphrase.isNotEmpty;

  SyncConfig copyWith({int? lastSyncAt}) => SyncConfig(
    serverUrl: serverUrl,
    token: token,
    passphrase: passphrase,
    intervalMinutes: intervalMinutes,
    lastSyncAt: lastSyncAt ?? this.lastSyncAt,
  );
}
