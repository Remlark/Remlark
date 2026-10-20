// Remlark 补丁：AEAD（AES-GCM）加解密后端可注入。
// 库内置的 pointycastle 纯 Dart GCM 实现仅约 1MB/s，应用可注入原生实现（如 OpenSSL）以获得硬件加速。
import 'dart:typed_data';

/// AES-GCM 加解密后端
abstract class SSHAeadBackend {
  /// 加密时 [input] 为明文，返回密文 + 16 字节标签；
  /// 解密时 [input] 为密文 + 16 字节标签，返回明文，认证失败返回 null
  Uint8List? process({
    required Uint8List key,
    required Uint8List nonce,
    required Uint8List aad,
    required Uint8List input,
    required bool forEncryption,
  });
}

/// 当前使用的后端；为 null 时使用内置纯 Dart 实现
SSHAeadBackend? sshAeadBackend;
