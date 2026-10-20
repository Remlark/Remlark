import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:pointycastle/export.dart';

/// Apple Remote Desktop 认证（RFB 安全类型 30），macOS 屏幕共享在未开启“VNC 密码”时使用。
///
/// 流程：服务器下发 DH 参数（生成元、素数、服务器公钥）→ 客户端生成密钥对并算出共享密钥 →
/// 以 MD5(共享密钥) 为 AES-128-ECB 密钥加密 128 字节凭据（用户名 64 字节 + 密码 64 字节）→
/// 回送“密文 + 客户端公钥”。
class ArdAuth {
  ArdAuth._();

  /// 安全类型编号
  static const securityType = 30;

  /// 用户名 / 密码各自占用的字节数（含结尾 0）
  static const _fieldLen = 64;

  /// 根据服务器参数计算客户端响应（密文 128 字节 + 客户端公钥 keyLen 字节）
  static Uint8List response({
    required int generator,
    required Uint8List prime,
    required Uint8List serverPublicKey,
    required String username,
    required String password,
    Random? random,
  }) {
    final rnd = random ?? Random.secure();
    final keyLen = prime.length;
    final p = _toBigInt(prime);
    final g = BigInt.from(generator);

    // 客户端私钥：与素数等长的随机数
    final priv = _toBigInt(Uint8List.fromList(List.generate(keyLen, (_) => rnd.nextInt(256))));
    final clientPub = g.modPow(priv, p);
    final shared = _toBigInt(serverPublicKey).modPow(priv, p);

    // 共享密钥按素数长度左补 0 后取 MD5 作为 AES 密钥
    final aesKey = MD5Digest().process(_toBytes(shared, keyLen));

    // 凭据：先填随机字节，再写入以 0 结尾的用户名与密码（与 macOS 客户端行为一致）
    final creds = Uint8List.fromList(List.generate(_fieldLen * 2, (_) => rnd.nextInt(256)));
    _writeField(creds, 0, username);
    _writeField(creds, _fieldLen, password);

    final cipher = _aesEcbEncrypt(aesKey, creds);
    return Uint8List.fromList([...cipher, ..._toBytes(clientPub, keyLen)]);
  }

  /// 写入一个以 0 结尾的 UTF-8 字段，超长截断到 63 字节
  static void _writeField(Uint8List buf, int offset, String value) {
    var bytes = utf8.encode(value);
    if (bytes.length > _fieldLen - 1) bytes = bytes.sublist(0, _fieldLen - 1);
    buf.setRange(offset, offset + bytes.length, bytes);
    buf[offset + bytes.length] = 0;
  }

  /// AES-128-ECB 加密（输入长度为 16 的倍数，无填充）
  static Uint8List _aesEcbEncrypt(Uint8List key, Uint8List data) {
    final aes = AESEngine()..init(true, KeyParameter(key));
    final out = Uint8List(data.length);
    for (var i = 0; i < data.length; i += 16) {
      aes.processBlock(data, i, out, i);
    }
    return out;
  }

  /// 大端字节 → 非负大整数
  static BigInt _toBigInt(Uint8List bytes) {
    var r = BigInt.zero;
    for (final b in bytes) {
      r = (r << 8) | BigInt.from(b);
    }
    return r;
  }

  /// 非负大整数 → 定长大端字节（左补 0）
  static Uint8List _toBytes(BigInt v, int len) {
    final out = Uint8List(len);
    var x = v;
    for (var i = len - 1; i >= 0 && x > BigInt.zero; i--) {
      out[i] = (x & BigInt.from(0xff)).toInt();
      x = x >> 8;
    }
    return out;
  }
}
