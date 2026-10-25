// 多平台测试 P-30：应用产品名与启动入口保持 Remlark 大小写一致。
import 'package:flutter_test/flutter_test.dart';

import '../utils/source_text.dart';

/// 读取受版本控制的配置，避免宿主文件系统忽略大小写掩盖发布错误；统一 LF 以兼容 Windows 检出。
String read(String path) => readSourceText(path);

/// 在三个宿主系统都检查全部平台的应用名称及兼容标识。
void main() {
  test('P-30 macOS 产品、工程和打包入口名称一致', () {
    expect(
      read('macos/Runner/Configs/AppInfo.xcconfig'),
      contains('PRODUCT_NAME = Remlark'),
    );
    for (final path in [
      'macos/Runner.xcodeproj/project.pbxproj',
      'macos/Runner.xcodeproj/xcshareddata/xcschemes/Runner.xcscheme',
      'tools/release/prepare.py',
      'tools/release/macos_signing.py',
    ]) {
      expect(read(path), contains('Remlark.app'), reason: path);
      expect(read(path), isNot(contains('remlark.app')), reason: path);
    }
    expect(read('Makefile'), contains('APP_NAME   := Remlark'));
    expect(
      read('macos/Runner/Configs/AppInfo.xcconfig'),
      contains('PRODUCT_BUNDLE_IDENTIFIER = com.remlark.remlark'),
    );
  });

  test('P-30 Windows 产品属性、可执行文件与快捷方式一致', () {
    expect(
      read('windows/CMakeLists.txt'),
      contains('set(BINARY_NAME "Remlark")'),
    );
    final resource = read('windows/runner/Runner.rc');
    for (final property in ['FileDescription', 'InternalName', 'ProductName']) {
      expect(resource, contains('VALUE "$property", "Remlark"'));
    }
    for (final path in [
      'windows/runner/Runner.rc',
      'windows/packaging/remlark.iss',
      'windows/packaging/build.ps1',
    ]) {
      expect(read(path), contains('Remlark.exe'), reason: path);
      expect(read(path), isNot(contains('remlark.exe')), reason: path);
    }
  });

  test('P-30 Linux 区分大小写的桌面入口与打包路径一致', () {
    expect(
      read('linux/CMakeLists.txt'),
      contains('set(BINARY_NAME "Remlark")'),
    );
    expect(
      read('linux/packaging/com.remlark.remlark.desktop'),
      contains('Exec=Remlark\n'),
    );
    final packaging = read('linux/packaging/build.py');
    expect(packaging, contains("'usr/bin/Remlark'"));
    expect(packaging, contains("'/opt/remlark/Remlark'"));
    // Debian 包名必须为小写，沿用包标识以支持覆盖安装。
    expect(packaging, contains('Package: remlark'));
    expect(
      read('linux/packaging/install-desktop.py'),
      contains("bundle / 'Remlark'"),
    );
  });
}
