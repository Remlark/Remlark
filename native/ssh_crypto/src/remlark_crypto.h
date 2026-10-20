// Remlark SSH 加密原生库：基于 OpenSSL（静态链接）提供硬件加速的加解密，供 Dart FFI 调用
#ifndef REMLARK_CRYPTO_H
#define REMLARK_CRYPTO_H

#include <stdint.h>

#ifdef _WIN32
#define RMK_CRYPTO_API __declspec(dllexport)
#else
#define RMK_CRYPTO_API __attribute__((visibility("default")))
#endif

#define RMK_GCM_TAG_SIZE 16
#define RMK_GCM_NONCE_SIZE 12

// 返回值
#define RMK_CRYPTO_OK 0
#define RMK_CRYPTO_AUTH_FAILED (-1)
#define RMK_CRYPTO_ERROR (-2)

// 库版本（用于检测原生库是否可用）
RMK_CRYPTO_API int32_t rmk_crypto_version(void);

// AES-GCM 加解密（SSH aes128-gcm@openssh.com / aes256-gcm@openssh.com）。
// key_len 为 16 或 32；nonce 为 12 字节；aad 为 SSH 包长度字段。
// 加密：in 为明文（in_len 字节），out 写入密文 + 16 字节标签（in_len + 16 字节）。
// 解密：in 为密文 + 16 字节标签（in_len 含标签），out 写入明文（in_len - 16 字节）；标签不符返回 RMK_CRYPTO_AUTH_FAILED。
RMK_CRYPTO_API int32_t rmk_crypto_aes_gcm(int32_t encrypt, const uint8_t *key, int32_t key_len, const uint8_t *nonce,
                                          const uint8_t *aad, int32_t aad_len, const uint8_t *in, int32_t in_len,
                                          uint8_t *out);

#endif
