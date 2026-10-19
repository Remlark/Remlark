import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';

/// 通用加密工具：AES-256-GCM 加解密、PBKDF2 派生密钥、安全随机数。
/// 本地密码存储与同步端到端加密共用这里的实现，避免重复代码。
class CryptoUtils {
  CryptoUtils._();

  static final AesGcm _aes = AesGcm.with256bits();
  static final Random _random = Random.secure();

  /// 加密数据格式前缀，便于以后升级算法时做版本区分
  static const String _prefix = 'v1:';

  /// 生成 [length] 字节的安全随机数
  static Uint8List randomBytes(int length) {
    final out = Uint8List(length);
    for (var i = 0; i < length; i++) {
      out[i] = _random.nextInt(256);
    }
    return out;
  }

  /// 使用 32 字节密钥对字节数据做 AES-GCM 加密，输出 nonce + 密文 + mac
  static Future<Uint8List> encryptBytes(List<int> key, List<int> plain) async {
    final box = await _aes.encrypt(plain, secretKey: SecretKey(key));
    return box.concatenation();
  }

  /// 解密 [encryptBytes] 的输出，密钥错误或数据被篡改时抛出异常
  static Future<Uint8List> decryptBytes(List<int> key, List<int> data) async {
    final box = SecretBox.fromConcatenation(
      data,
      nonceLength: _aes.nonceLength,
      macLength: _aes.macAlgorithm.macLength,
    );
    final plain = await _aes.decrypt(box, secretKey: SecretKey(key));
    return Uint8List.fromList(plain);
  }

  /// 加密字符串，输出带版本前缀的 base64 文本
  static Future<String> encryptString(List<int> key, String plain) async {
    final data = await encryptBytes(key, utf8.encode(plain));
    return '$_prefix${base64Encode(data)}';
  }

  /// 解密 [encryptString] 的输出
  static Future<String> decryptString(List<int> key, String cipher) async {
    if (!cipher.startsWith(_prefix)) {
      throw const FormatException('unknown cipher format');
    }
    final data = base64Decode(cipher.substring(_prefix.length));
    return utf8.decode(await decryptBytes(key, data));
  }

  /// 使用 PBKDF2-HMAC-SHA256 从口令派生 32 字节密钥
  static Future<Uint8List> deriveKey(String passphrase, List<int> salt, {int iterations = 100000}) async {
    final pbkdf2 = Pbkdf2(macAlgorithm: Hmac.sha256(), iterations: iterations, bits: 256);
    final key = await pbkdf2.deriveKeyFromPassword(password: passphrase, nonce: salt);
    return Uint8List.fromList(await key.extractBytes());
  }

  /// 计算 SHA-256 摘要
  static Future<Uint8List> sha256(List<int> data) async {
    final hash = await Sha256().hash(data);
    return Uint8List.fromList(hash.bytes);
  }
}
