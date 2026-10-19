import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:remlark/modules/ai/agent_interface.dart';
import 'package:remlark/modules/ai/ui/chat_message_view.dart';
import 'package:remlark/modules/import_export/ssh_config_parser.dart';
import 'package:remlark/modules/keys/key_utils.dart';
import 'package:remlark/modules/ssh/os_detector.dart';
import 'package:remlark/utils/crypto_utils.dart';
import 'package:remlark/utils/des.dart';
import 'package:remlark/utils/shell_utils.dart';

String _hex(List<int> b) => b.map((e) => e.toRadixString(16).padLeft(2, '0')).join();

List<int> _unhex(String s) => [for (var i = 0; i < s.length; i += 2) int.parse(s.substring(i, i + 2), radix: 16)];

void main() {
  test('DES 标准测试向量', () {
    final des = Des(_unhex('133457799bbcdff1'));
    expect(_hex(des.encryptBlock(_unhex('0123456789abcdef'))), '85e813540f0ab405');
  });

  test('AES-GCM 加解密往返', () async {
    final key = CryptoUtils.randomBytes(32);
    final c = await CryptoUtils.encryptString(key, '你好 secret');
    expect(await CryptoUtils.decryptString(key, c), '你好 secret');
    expect(() => CryptoUtils.decryptString(CryptoUtils.randomBytes(32), c), throwsA(anything));
  });

  test('生成的 ed25519 密钥可被 dartssh2 解析且公钥一致', () async {
    final g = await KeyUtils.generateEd25519('test@remlark');
    final pub = KeyUtils.derivePublic(g.privatePem, null, 'test@remlark');
    expect(pub.keyType, 'ssh-ed25519');
    expect(pub.publicLine, g.publicLine);
    expect(KeyUtils.isEncrypted(g.privatePem), isFalse);
  });

  test('系统探测输出解析', () {
    const ubuntu =
        'Linux\nNAME="Ubuntu"\nVERSION_ID="22.04"\nID=ubuntu\nID_LIKE=debian\nPRETTY_NAME="Ubuntu 22.04.3 LTS"\n__END__';
    final u = OsDetector.parse(ubuntu)!;
    expect(u.id, 'ubuntu');
    expect(u.name, 'Ubuntu 22.04.3 LTS');
    const rhel = 'Linux\nID="rhel"\nPRETTY_NAME="Red Hat Enterprise Linux 9.2 (Plow)"\n';
    expect(OsDetector.parse(rhel)!.id, 'rhel');
    const like = 'Linux\nID="someos"\nID_LIKE="rhel centos fedora"\n';
    expect(OsDetector.parse(like)!.id, 'rhel');
    expect(OsDetector.parse('Darwin\nProductName: macOS\nProductVersion: 14.5\n')!.id, 'macos');
  });

  test('ssh config 解析', () {
    const cfg = '''
Host *
  ServerAliveInterval 30
Host bastion
  HostName 1.2.3.4
  User admin
  Port 2222
Host web db
  HostName 10.0.0.5
  User root
  ProxyJump bastion
  IdentityFile ~/.ssh/id_ed25519
''';
    final e = SshConfigParser.parse(cfg);
    expect(e.map((x) => x.alias), ['bastion', 'web', 'db']);
    expect(e[0].port, 2222);
    expect(e[1].proxyJump, ['bastion']);
    expect(e[2].hostName, '10.0.0.5');
    expect(e[1].identityFile, endsWith('.ssh/id_ed25519'));
  });

  test('shell 工具', () {
    expect(ShellUtils.quote("a'b"), "'a'\\''b'");
    expect(ShellUtils.parentRemote('/a/b/c'), '/a/b');
    expect(ShellUtils.parentRemote('/a'), '/');
    expect(ShellUtils.joinRemote('/a/', 'b'), '/a/b');
  });

  test('聊天消息代码块拆分与 token 估算', () {
    final parts = ChatMessageView.split('看这里:\n```bash\nls -la\n```\n结束');
    expect(parts.where((p) => p.$1).single.$3, 'ls -la');
    expect(estimateTokens('hello world'), 3);
    expect(estimateTokens('你好'), 2);
  });

  test('OpenSSH 公钥行格式', () async {
    final g = await KeyUtils.generateEd25519('c');
    final parts = g.publicLine.split(' ');
    expect(parts[0], 'ssh-ed25519');
    expect(base64Decode(parts[1]).length, 51);
  });
}
