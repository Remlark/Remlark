import 'dart:ffi';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:remlark/modules/updates/platform/update_platform.dart';
import 'package:remlark/modules/updates/platform/update_platform_linux.dart';
import 'package:remlark/modules/updates/platform/update_platform_macos.dart';
import 'package:remlark/modules/updates/platform/update_platform_windows.dart';

/// P-18：六种平台/架构安装包映射、安装方式及不支持架构。
void main() {
  test('P-18 三平台两种架构的附件与 Release 清单一致', () {
    for (final abi in [Abi.macosArm64, Abi.macosX64]) {
      expect(MacosUpdatePlatform(abi).assetName('1.2.0'), 'Remlark-macos.zip');
    }
    expect(
      WindowsUpdatePlatform(Abi.windowsX64).assetName('1.2.0'),
      'Remlark-1.2.0-windows-x64-setup.exe',
    );
    // 只发布 x64；ARM64 设备运行仿真 x64 版本，原生 ARM64 构建没有安装包。
    expect(WindowsUpdatePlatform(Abi.windowsArm64).assetName('1.2.0'), isNull);
    expect(
      LinuxUpdatePlatform(Abi.linuxX64).assetName('1.2.0'),
      'Remlark-linux-x64.tar.gz',
    );
    expect(
      LinuxUpdatePlatform(Abi.linuxArm64).assetName('1.2.0'),
      'Remlark-linux-arm64.tar.gz',
    );
    expect(
      LinuxUpdatePlatform(
        Abi.linuxX64,
        executable: '/opt/remlark/Remlark',
      ).assetName('1.2.0'),
      'Remlark-1.2.0-linux-amd64.deb',
    );
    expect(
      LinuxUpdatePlatform(
        Abi.linuxArm64,
        executable: '/opt/remlark/Remlark',
      ).assetName('1.2.0'),
      'Remlark-1.2.0-linux-arm64.deb',
    );
    expect(MacosUpdatePlatform(Abi.linuxIA32).assetName('1.2.0'), isNull);
    expect(WindowsUpdatePlatform(Abi.windowsIA32).assetName('1.2.0'), isNull);
    expect(LinuxUpdatePlatform(Abi.linuxIA32).assetName('1.2.0'), isNull);
  });
  test('P-18 当前系统选择正确实现', () {
    final platform = UpdatePlatform.current();
    if (Platform.isMacOS) expect(platform, isA<MacosUpdatePlatform>());
    if (Platform.isWindows) expect(platform, isA<WindowsUpdatePlatform>());
    if (Platform.isLinux) expect(platform, isA<LinuxUpdatePlatform>());
    expect(platform.assetName('1.2.0'), isNotNull);
  });
}
