import 'dart:math';
import 'dart:typed_data';

import 'package:dartssh2/dartssh2.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pointycastle/export.dart';
import 'package:remlark/modules/ssh/crypto/native_crypto.dart';

/// pointycastle 的 AES-GCM（dartssh2 原纯 Dart 实现），作为对照
Uint8List _dartGcm(Uint8List key, Uint8List nonce, Uint8List aad, Uint8List input, bool enc) {
  final c = GCMBlockCipher(AESEngine())..init(enc, AEADParameters(KeyParameter(key), 128, nonce, aad));
  return c.process(input);
}

Uint8List _random(Random r, int n) => Uint8List.fromList(List.generate(n, (_) => r.nextInt(256)));

void main() {
  final available = NativeSshCrypto.install();

  test('原生 AES-GCM 与纯 Dart 实现结果一致，篡改标签认证失败', () {
    if (!available) return markTestSkipped('原生加密库未编译（make crypto-lib）');
    final backend = sshAeadBackend!;
    final r = Random(1);
    for (final keyLen in [16, 32]) {
      for (final len in [16, 32, 4096, 32768 + 16]) {
        final key = _random(r, keyLen), nonce = _random(r, 12), aad = _random(r, 4), plain = _random(r, len);
        final enc = backend.process(key: key, nonce: nonce, aad: aad, input: plain, forEncryption: true)!;
        expect(enc, _dartGcm(key, nonce, aad, plain, true));
        final dec = backend.process(key: key, nonce: nonce, aad: aad, input: enc, forEncryption: false);
        expect(dec, plain);
        enc[enc.length - 1] ^= 1;
        expect(backend.process(key: key, nonce: nonce, aad: aad, input: enc, forEncryption: false), isNull);
      }
    }
  });
}
