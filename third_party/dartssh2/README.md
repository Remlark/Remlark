# dartssh2（Remlark 内置副本）

基于 [dartssh2](https://github.com/vicajilau/dartssh2) 4.1.0（MIT，见 LICENSE），仅做以下修改：

- 新增 `lib/src/ssh_aead_backend.dart`：AES-GCM 加解密后端可注入（`sshAeadBackend`），
  `SSHTransport._processAead` 优先使用注入的后端。Remlark 注入基于 OpenSSL 的原生实现（native/ssh_crypto），
  纯 Dart GCM 仅约 1MB/s，原生实现利用 CPU AES 指令可达数 GB/s。

升级上游版本时需重新应用上述补丁。
