import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:remlark/utils/crypto_utils.dart';

void main() {
  final key = Uint8List(32);

  test('同步 JSON 先 gzip 再加密，压缩后的密文能完整恢复中文配置', () async {
    final plain = jsonEncode({
      'name': '生产服务器',
      'note': List.filled(1000, 'SSH/VNC/RDP 配置与凭据').join(),
    });
    final cipher = await CryptoUtils.encryptCompressedString(key, plain);
    expect(cipher, startsWith('v2:gzip:'));
    expect(cipher.length, lessThan(plain.length ~/ 2));
    expect(cipher, isNot(contains('生产服务器')));
    final compressed = await CryptoUtils.decryptBytes(
      key,
      base64Decode(cipher.substring('v2:gzip:'.length)),
    );
    expect(compressed.take(2), [0x1f, 0x8b], reason: '解密得到 gzip 数据，证明压缩发生在加密前');
    expect(await CryptoUtils.decryptCompressedString(key, cipher), plain);
  });

  test('新客户端仍可读取旧版未压缩密文', () async {
    final old = await CryptoUtils.encryptString(key, '{"host":"old"}');
    expect(
      await CryptoUtils.decryptCompressedString(key, old),
      '{"host":"old"}',
    );
  });

  test('压缩密文使用错误口令时认证失败', () async {
    final cipher = await CryptoUtils.encryptCompressedString(key, 'secret');
    await expectLater(
      CryptoUtils.decryptCompressedString(
        Uint8List.fromList(List.filled(32, 1)),
        cipher,
      ),
      throwsA(anything),
    );
  });

  test('篡改压缩密文不能绕过认证', () async {
    final cipher = await CryptoUtils.encryptCompressedString(key, 'secret');
    final data = base64Decode(cipher.substring('v2:gzip:'.length));
    data[data.length - 1] ^= 1;
    await expectLater(
      CryptoUtils.decryptCompressedString(key, 'v2:gzip:${base64Encode(data)}'),
      throwsA(anything),
    );
  });

  test('已通过加密认证但不含合法 gzip 的载荷仍被拒绝', () async {
    final data = await CryptoUtils.encryptBytes(key, utf8.encode('not gzip'));
    await expectLater(
      CryptoUtils.decryptCompressedString(key, 'v2:gzip:${base64Encode(data)}'),
      throwsA(anything),
    );
  });

  test('未知压缩格式拒绝解析，不影响原有本地加密格式', () async {
    await expectLater(
      CryptoUtils.decryptCompressedString(key, 'v3:unknown:data'),
      throwsFormatException,
    );
    final local = await CryptoUtils.encryptString(key, 'local secret');
    expect(local, startsWith('v1:'));
    expect(await CryptoUtils.decryptString(key, local), 'local secret');
  });
}
