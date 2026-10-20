import 'dart:convert';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:dartssh2/dartssh2.dart';

import '../../utils/crypto_utils.dart';

/// 生成的密钥对（OpenSSH 格式）
class GeneratedKey {
  const GeneratedKey(this.privatePem, this.publicLine, this.keyType);

  final String privatePem;
  final String publicLine;
  final String keyType;
}

/// 密钥工具：生成 ed25519 密钥、解析私钥并推导公钥
class KeyUtils {
  KeyUtils._();

  /// 写入 SSH string（uint32 长度 + 数据）
  static void _writeString(BytesBuilder b, List<int> data) {
    final len = ByteData(4)..setUint32(0, data.length);
    b.add(len.buffer.asUint8List());
    b.add(data);
  }

  static void _writeUint32(BytesBuilder b, int v) {
    final d = ByteData(4)..setUint32(0, v);
    b.add(d.buffer.asUint8List());
  }

  /// 生成 ed25519 密钥，输出 OpenSSH 私钥 PEM 与公钥行
  static Future<GeneratedKey> generateEd25519(String comment) async {
    final algo = Ed25519();
    final pair = await algo.newKeyPair();
    final seed = await pair.extractPrivateKeyBytes();
    final pub = (await pair.extractPublicKey()).bytes;
    const type = 'ssh-ed25519';

    // 公钥 blob
    final pubBlob = BytesBuilder();
    _writeString(pubBlob, utf8.encode(type));
    _writeString(pubBlob, pub);
    final pubBytes = pubBlob.toBytes();

    // 私钥段
    final check = ByteData.sublistView(CryptoUtils.randomBytes(4)).getUint32(0);
    final priv = BytesBuilder();
    _writeUint32(priv, check);
    _writeUint32(priv, check);
    _writeString(priv, utf8.encode(type));
    _writeString(priv, pub);
    _writeString(priv, [...seed, ...pub]);
    _writeString(priv, utf8.encode(comment));
    // 按 8 字节对齐填充 1,2,3...
    var pad = 1;
    while (priv.length % 8 != 0) {
      priv.addByte(pad++);
    }

    final out = BytesBuilder();
    out.add(utf8.encode('openssh-key-v1'));
    out.addByte(0);
    _writeString(out, utf8.encode('none'));
    _writeString(out, utf8.encode('none'));
    _writeString(out, const []);
    _writeUint32(out, 1);
    _writeString(out, pubBytes);
    _writeString(out, priv.toBytes());

    final b64 = base64Encode(out.toBytes());
    final lines = StringBuffer('-----BEGIN OPENSSH PRIVATE KEY-----\n');
    for (var i = 0; i < b64.length; i += 70) {
      lines.writeln(b64.substring(i, i + 70 > b64.length ? b64.length : i + 70));
    }
    lines.writeln('-----END OPENSSH PRIVATE KEY-----');
    final publicLine = '$type ${base64Encode(pubBytes)} $comment'.trim();
    return GeneratedKey(lines.toString(), publicLine, type);
  }

  /// 读取 blob 中第一个 SSH string（即公钥类型名）
  static String _blobType(Uint8List blob) {
    if (blob.length < 4) return '';
    final len = ByteData.sublistView(blob, 0, 4).getUint32(0);
    if (blob.length < 4 + len) return '';
    return utf8.decode(blob.sublist(4, 4 + len));
  }

  /// 解析私钥 PEM（可带口令），返回 dartssh2 的密钥对列表；失败抛出异常
  static List<SSHKeyPair> parse(String pem, [String? passphrase]) {
    return SSHKeyPair.fromPem(pem, passphrase?.isEmpty == true ? null : passphrase);
  }

  /// 私钥是否被口令加密
  static bool isEncrypted(String pem) {
    try {
      return SSHKeyPair.isEncryptedPem(pem);
    } catch (_) {
      return false;
    }
  }

  /// 从私钥推导公钥行与类型
  static ({String publicLine, String keyType}) derivePublic(String pem, [String? passphrase, String comment = '']) {
    final pair = parse(pem, passphrase).first;
    final blob = pair.toPublicKey().encode();
    final type = _blobType(blob);
    return (publicLine: '$type ${base64Encode(blob)} $comment'.trim(), keyType: type);
  }

  /// 公钥指纹（与 ssh-keygen -l 一致）：SHA256:无填充 base64
  static Future<String> fingerprint(String publicLine) async {
    final parts = publicLine.trim().split(RegExp(r'\s+'));
    if (parts.length < 2) return '';
    try {
      final digest = await CryptoUtils.sha256(base64Decode(parts[1]));
      return 'SHA256:${base64Encode(digest).replaceAll('=', '')}';
    } catch (_) {
      return '';
    }
  }
}
