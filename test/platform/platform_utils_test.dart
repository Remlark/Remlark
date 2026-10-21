import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:remlark/utils/file_permissions/file_permissions.dart';
import 'package:remlark/utils/file_permissions/file_permissions_posix.dart';
import 'package:remlark/utils/file_permissions/file_permissions_windows.dart';
import 'package:remlark/utils/platform_utils.dart';
import 'package:remlark/utils/secret_store.dart';

/// 多平台测试 P-04：主目录、PATH 查找可执行文件、敏感文件权限（见 docs/multi-platform-testing.md）
void main() {
  test('主目录：存在且为绝对路径（Windows 取 USERPROFILE）', () {
    final home = PlatformUtils.homeDir();
    expect(p.isAbsolute(home), isTrue);
    expect(Directory(home).existsSync(), isTrue);
  });

  test('which：在 PATH 中找到系统自带程序，Windows 自动补 .exe 后缀，找不到返回 null', () {
    if (Platform.isWindows) {
      final cmd = PlatformUtils.which('cmd');
      expect(cmd, isNotNull);
      expect(cmd!.toLowerCase(), endsWith('.exe'));
    } else {
      expect(PlatformUtils.which('sh'), isNotNull);
    }
    expect(PlatformUtils.which('remlark-no-such-program'), isNull);
    expect(PlatformUtils.whichAny(['remlark-no-such-program', Platform.isWindows ? 'cmd' : 'sh']), isNotNull);
  });

  test('isUnixDesktop：macOS / Linux 为 true，Windows 为 false', () {
    expect(PlatformUtils.isUnixDesktop, !Platform.isWindows);
  });

  test('文件权限：current() 选择对应实现；Windows 用 icacls 去掉继承权限、只授权当前用户', () {
    expect(FilePermissions.current(), Platform.isWindows ? isA<WindowsFilePermissions>() : isA<PosixFilePermissions>());
    expect(WindowsFilePermissions.icaclsArgs(r'C:\d\master.key', r'PC\me', directory: false), [
      r'C:\d\master.key',
      '/inheritance:r',
      '/grant:r',
      r'PC\me:F',
    ]);
    expect(WindowsFilePermissions.icaclsArgs(r'C:\d', 'me', directory: true).last, 'me:(OI)(CI)F');
    if (Platform.isWindows) expect(WindowsFilePermissions.currentUser(), isNotNull);
  });

  test('主密钥文件：POSIX 平台权限为 600 / 700，Windows 只有当前用户的权限', () async {
    final tmp = await Directory.systemTemp.createTemp('rmk-perm-');
    addTearDown(() => tmp.delete(recursive: true));
    final f = File(p.join(tmp.path, 'master.key'))..writeAsStringSync('x');
    await PlatformUtils.restrictPermissions(f.path);
    await PlatformUtils.restrictDirectory(tmp.path);
    if (!Platform.isWindows) {
      expect(f.statSync().mode & 0x1FF, 0x180, reason: '应为 0600');
      expect(tmp.statSync().mode & 0x1FF, 0x1C0, reason: '应为 0700');
    } else {
      // icacls 输出中有当前用户，且没有继承来的权限（(I) 标记；账户名会随系统语言变化，不按名称判断）
      final user = WindowsFilePermissions.currentUser()!.split(r'\').last.toLowerCase();
      for (final path in [f.path, tmp.path]) {
        final acl = '${(await Process.run('icacls', [path])).stdout}'.toLowerCase();
        expect(acl, contains(user), reason: acl);
        expect(acl, isNot(contains('(i)')), reason: '仍有继承的权限：$acl');
      }
    }

    // SecretStore.init 在数据目录生成主密钥并收紧权限
    final data = Directory(p.join(tmp.path, 'data'))..createSync();
    PlatformUtils.overrideDataDir(data);
    final store = await SecretStore.init();
    final key = File(p.join(data.path, 'master.key'));
    expect(key.existsSync(), isTrue);
    if (!Platform.isWindows) expect(key.statSync().mode & 0x1FF, 0x180);
    if (Platform.isWindows) expect('${(await Process.run('icacls', [key.path])).stdout}'.toLowerCase(), isNot(contains('(i)')));
    expect(await store.open(await store.seal('pw')), 'pw');
  });
}
