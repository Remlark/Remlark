import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart' as p;

import 'crypto_utils.dart';
import 'platform_utils.dart';

/// 本地敏感字段加密存储：主密钥保存在应用数据目录（权限 600），
/// 数据库中的密码、私钥、API Key 等均以 AES-GCM 密文存储。
class SecretStore {
  SecretStore._(this._key);

  final Uint8List _key;

  static SecretStore? _instance;

  /// 全局实例，需先调用 [init]
  static SecretStore get instance {
    final s = _instance;
    if (s == null) throw StateError('SecretStore not initialized');
    return s;
  }

  /// 初始化：读取或生成本地主密钥
  static Future<SecretStore> init() async {
    if (_instance != null) return _instance!;
    final dir = await PlatformUtils.dataDir();
    final file = File(p.join(dir.path, 'master.key'));
    Uint8List key;
    if (file.existsSync()) {
      key = base64Decode(file.readAsStringSync().trim());
    } else {
      key = CryptoUtils.randomBytes(32);
      file.writeAsStringSync(base64Encode(key));
      await PlatformUtils.restrictPermissions(file.path);
    }
    _instance = SecretStore._(key);
    return _instance!;
  }

  /// 测试用：使用指定密钥初始化（不读写磁盘）
  static void initForTest(Uint8List key) => _instance = SecretStore._(key);

  /// 加密字段，空字符串或 null 返回 null（不存储）
  Future<String?> seal(String? plain) async {
    if (plain == null || plain.isEmpty) return null;
    return CryptoUtils.encryptString(_key, plain);
  }

  /// 解密字段，失败返回 null（例如主密钥被替换）
  Future<String?> open(String? cipher) async {
    if (cipher == null || cipher.isEmpty) return null;
    try {
      return await CryptoUtils.decryptString(_key, cipher);
    } catch (_) {
      return null;
    }
  }
}
