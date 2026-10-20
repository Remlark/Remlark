// ignore_for_file: non_constant_identifier_names

// SSH 加密原生库（native/ssh_crypto）的 FFI 绑定与 dartssh2 AES-GCM 后端。
// 库由 hook/build.dart 作为代码资源打包，通过 @DefaultAsset 自动解析。
@DefaultAsset('package:remlark/crypto')
library;

import 'dart:ffi';
import 'dart:typed_data';

import 'package:dartssh2/dartssh2.dart';

import '../../../utils/app_log.dart';

@Native<Int32 Function()>(isLeaf: true)
external int rmk_crypto_version();

@Native<
  Int32 Function(
    Int32,
    Pointer<Uint8>,
    Int32,
    Pointer<Uint8>,
    Pointer<Uint8>,
    Int32,
    Pointer<Uint8>,
    Int32,
    Pointer<Uint8>,
  )
>(isLeaf: true)
external int rmk_crypto_aes_gcm(
  int encrypt,
  Pointer<Uint8> key,
  int keyLen,
  Pointer<Uint8> nonce,
  Pointer<Uint8> aad,
  int aadLen,
  Pointer<Uint8> input,
  int inLen,
  Pointer<Uint8> output,
);

/// SSH 原生加密：检测原生库并注入 dartssh2
class NativeSshCrypto {
  NativeSshCrypto._();

  static bool? _installed;

  /// 安装原生 AES-GCM 后端，返回是否可用（只检测一次；库缺失时 SSH 退回纯 Dart 加密）
  static bool install() {
    final done = _installed;
    if (done != null) return done;
    try {
      rmk_crypto_version();
      sshAeadBackend = _NativeAeadBackend();
      _installed = true;
      AppLog.i('ssh', '已启用原生 AES-GCM 加密（OpenSSL）');
    } catch (e) {
      _installed = false;
      AppLog.w('ssh', '原生加密库不可用，使用纯 Dart 加密（传输较慢）', e);
    }
    return _installed!;
  }
}

/// 基于 OpenSSL 的 AES-GCM 后端：typed data 直接以指针传入 leaf 调用，无额外拷贝
class _NativeAeadBackend implements SSHAeadBackend {
  static const _tagSize = 16;

  @override
  Uint8List? process({
    required Uint8List key,
    required Uint8List nonce,
    required Uint8List aad,
    required Uint8List input,
    required bool forEncryption,
  }) {
    final outLen = forEncryption ? input.length + _tagSize : input.length - _tagSize;
    if (outLen < 0) return null;
    final out = Uint8List(outLen);
    final rc = rmk_crypto_aes_gcm(
      forEncryption ? 1 : 0,
      key.address,
      key.length,
      nonce.address,
      aad.address,
      aad.length,
      input.address,
      input.length,
      out.address,
    );
    if (rc == 0) return out;
    if (rc == -1) return null;
    throw StateError('native AES-GCM failed: $rc');
  }
}
