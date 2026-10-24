/// 同步传输协议版本；与应用 VERSION、主机快照和加密封装版本分别演进。
abstract final class SyncProtocol {
  static const version = '1.0';
  static const legacyVersion = '1.0';
  static const header = 'x-remlark-sync-protocol';

  /// 未声明版本的历史服务端只视为 1.0，不随客户端当前版本自动升级。
  static void verify(String? remoteVersion) {
    if ((remoteVersion ?? legacyVersion) != version) {
      throw SyncProtocolException(remoteVersion ?? legacyVersion);
    }
  }
}

/// 协议不兼容时阻止读写；界面通过同名翻译键展示升级提示。
class SyncProtocolException implements Exception {
  const SyncProtocolException(this.remoteVersion);
  final String? remoteVersion;

  /// 返回翻译键，供同步状态和连接检测统一展示协议错误。
  @override
  String toString() => 'sync.error.protocol';
}
