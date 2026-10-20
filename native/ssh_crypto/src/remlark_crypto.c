// Remlark SSH 加密原生库实现（OpenSSL EVP 接口，自动使用 AES-NI / ARMv8 AES 指令）
#include "remlark_crypto.h"

#include <openssl/evp.h>

/// 库版本
int32_t rmk_crypto_version(void) { return 1; }

/// 按密钥长度选择 GCM 算法
static const EVP_CIPHER *gcm_cipher(int32_t key_len) {
  switch (key_len) {
    case 16: return EVP_aes_128_gcm();
    case 32: return EVP_aes_256_gcm();
    default: return NULL;
  }
}

/// AES-GCM 加解密，见头文件说明
int32_t rmk_crypto_aes_gcm(int32_t encrypt, const uint8_t *key, int32_t key_len, const uint8_t *nonce,
                           const uint8_t *aad, int32_t aad_len, const uint8_t *in, int32_t in_len, uint8_t *out) {
  const EVP_CIPHER *cipher = gcm_cipher(key_len);
  if (cipher == NULL || in_len < 0 || (!encrypt && in_len < RMK_GCM_TAG_SIZE)) return RMK_CRYPTO_ERROR;
  // 解密时输入末尾 16 字节为标签
  const int32_t data_len = encrypt ? in_len : in_len - RMK_GCM_TAG_SIZE;

  EVP_CIPHER_CTX *ctx = EVP_CIPHER_CTX_new();
  if (ctx == NULL) return RMK_CRYPTO_ERROR;
  int32_t rc = RMK_CRYPTO_ERROR;
  int len = 0;
  // GCM 默认 nonce 为 12 字节，与 SSH 一致，无需设置 IVLEN
  if (EVP_CipherInit_ex(ctx, cipher, NULL, key, nonce, encrypt ? 1 : 0) != 1) goto done;
  if (aad_len > 0 && EVP_CipherUpdate(ctx, NULL, &len, aad, aad_len) != 1) goto done;
  if (data_len > 0 && EVP_CipherUpdate(ctx, out, &len, in, data_len) != 1) goto done;
  if (encrypt) {
    if (EVP_CipherFinal_ex(ctx, out + data_len, &len) != 1) goto done;
    // 标签追加在密文之后
    if (EVP_CIPHER_CTX_ctrl(ctx, EVP_CTRL_GCM_GET_TAG, RMK_GCM_TAG_SIZE, out + data_len) != 1) goto done;
    rc = RMK_CRYPTO_OK;
  } else {
    // 设置期望标签后 Final 校验：不符即认证失败
    if (EVP_CIPHER_CTX_ctrl(ctx, EVP_CTRL_GCM_SET_TAG, RMK_GCM_TAG_SIZE, (void *)(in + data_len)) != 1) goto done;
    rc = EVP_CipherFinal_ex(ctx, out + data_len, &len) == 1 ? RMK_CRYPTO_OK : RMK_CRYPTO_AUTH_FAILED;
  }
done:
  EVP_CIPHER_CTX_free(ctx);
  return rc;
}
