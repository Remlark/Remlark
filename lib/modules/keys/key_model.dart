/// SSH 密钥领域模型
class KeyEntry {
  const KeyEntry({
    required this.uuid,
    required this.name,
    required this.keyType,
    required this.privateKey,
    this.passphrase,
    required this.publicKey,
    required this.createdAt,
  });

  final String uuid;
  final String name;
  final String keyType;

  /// 私钥 PEM（明文，仅在内存中）
  final String privateKey;
  final String? passphrase;

  /// OpenSSH 公钥行，如 "ssh-ed25519 AAAA... comment"
  final String publicKey;
  final int createdAt;

  /// 可移植 JSON（导出 / 同步载荷）
  Map<String, dynamic> toJson() => {
    'uuid': uuid,
    'name': name,
    'keyType': keyType,
    'privateKey': privateKey,
    if (passphrase != null) 'passphrase': passphrase,
    'publicKey': publicKey,
    'createdAt': createdAt,
  };

  factory KeyEntry.fromJson(Map<String, dynamic> j) => KeyEntry(
    uuid: j['uuid'] as String,
    name: j['name'] as String? ?? '',
    keyType: j['keyType'] as String? ?? '',
    privateKey: j['privateKey'] as String? ?? '',
    passphrase: j['passphrase'] as String?,
    publicKey: j['publicKey'] as String? ?? '',
    createdAt: (j['createdAt'] as num?)?.toInt() ?? DateTime.now().millisecondsSinceEpoch,
  );
}
