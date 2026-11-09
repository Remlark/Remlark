// 启动外部进程，ARM runner 上进程启动慢，放宽默认 30 秒时限。
@Timeout(Duration(minutes: 3))
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// 多平台测试 P-09：Linux 打包入口、架构选择与缺失原生库时的分发保护。
void main() {
  test('Debian 系统资源保留已有主题索引，只复制应用自有文件', () async {
    final result = await Process.run(Platform.isWindows ? 'python' : 'python3', ['-c', r'''
import importlib.util
from pathlib import Path
from tempfile import TemporaryDirectory
spec = importlib.util.spec_from_file_location('packaging', 'linux/packaging/build.py')
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)
with TemporaryDirectory() as directory:
    root = Path(directory)
    app, stage = root / 'app', root / 'stage'
    assets = {
        'applications/com.remlark.remlark.desktop': 'desktop',
        'icons/hicolor/256x256/apps/com.remlark.remlark.png': 'icon',
        'icons/hicolor/index.theme': 'bundled theme',
        'icons/hicolor/256x256/apps/other.png': 'other icon',
    }
    for relative, content in assets.items():
        source = app / 'share' / relative
        source.parent.mkdir(parents=True, exist_ok=True)
        source.write_text(content)
    theme = stage / 'usr/share/icons/hicolor/index.theme'
    theme.parent.mkdir(parents=True)
    theme.write_text('system theme')
    module.install_system_assets(app, stage)
    assert theme.read_text() == 'system theme'
    assert (stage / 'usr/share/applications/com.remlark.remlark.desktop').read_text() == 'desktop'
    assert (stage / 'usr/share/icons/hicolor/256x256/apps/com.remlark.remlark.png').read_text() == 'icon'
    assert not (stage / 'usr/share/icons/hicolor/256x256/apps/other.png').exists()
    theme.unlink()
    module.install_system_assets(app, stage)
    assert not theme.exists()
''']);
    expect(result.exitCode, 0, reason: '${result.stdout}\n${result.stderr}');
  });

  test('三个平台保留独立打包入口，Linux 生成 deb 与便携包', () {
    final makefile = File('Makefile').readAsStringSync();
    for (final target in ['mac:', 'linux:', 'windows:']) {
      expect(makefile, contains(target));
    }
    expect(makefile, contains('linux/packaging/build.py --arch \$(LINUX_ARCH)'));
    expect(makefile, contains('filter aarch64 arm64'));
    final script = File('linux/packaging/build.py').readAsStringSync();
    expect(script, contains("'x64': 'amd64', 'arm64': 'arm64'"));
    expect(File('linux/CMakeLists.txt').readAsStringSync(), contains('set(CMAKE_DISABLE_FIND_PACKAGE_JNI TRUE)'));
  });

  test('Linux 桌面入口能从包含中文和特殊字符的路径启动', () async {
    if (!Platform.isLinux) {
      expect(File('linux/packaging/install-desktop.py').readAsStringSync(), contains('Exec=/usr/bin/env'));
      return;
    }
    final root = Directory.systemTemp.createTempSync(r'rmk desktop 中文 % $ ` " \ ');
    addTearDown(() => root.deleteSync(recursive: true));
    final executable = File('${root.path}/Remlark');
    executable.writeAsStringSync(r'''#!/bin/sh
printf launched > "$(dirname "$0")/launched"
''');
    expect((await Process.run('chmod', ['755', executable.path])).exitCode, 0);
    File('linux/packaging/install-desktop.py').copySync('${root.path}/install-desktop.py');
    final applications = Directory('${root.path}/share/applications')..createSync(recursive: true);
    File('linux/packaging/com.remlark.remlark.desktop').copySync('${applications.path}/com.remlark.remlark.desktop');
    final icons = Directory('${root.path}/share/icons/hicolor/256x256/apps')..createSync(recursive: true);
    File('linux/packaging/icons/hicolor/256x256/apps/com.remlark.remlark.png')
        .copySync('${icons.path}/com.remlark.remlark.png');
    final environment = {'XDG_DATA_HOME': '${root.path}/data'};
    final install = await Process.run('python3', ['${root.path}/install-desktop.py'], environment: environment);
    expect(install.exitCode, 0, reason: '${install.stderr}');
    final desktop = '${root.path}/data/applications/com.remlark.remlark.desktop';
    final validate = await Process.run('desktop-file-validate', [desktop]);
    expect(validate.exitCode, 0, reason: '${validate.stderr}');
    // 用真正的 GIO 解析并启动，避免仅检查字符串而漏掉 %% 字段展开顺序的问题。
    final launch = await Process.run('gio', ['launch', desktop], environment: environment);
    expect(launch.exitCode, 0, reason: '${launch.stderr}');
    final marker = File('${root.path}/launched');
    for (var i = 0; i < 50 && !marker.existsSync(); i++) {
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
    expect(marker.readAsStringSync(), 'launched');
  });

  test('Linux 拒绝缺少原生库的 Release，且不生成不完整的分发包', () async {
    if (!Platform.isLinux) {
      // 安装格式属于 Linux；macOS / Windows 分别使用各自的打包入口。
      expect(File(Platform.isMacOS ? 'macos/Runner/Info.plist' : 'windows/packaging/build.ps1').existsSync(), isTrue);
      return;
    }
    final root = Directory.systemTemp.createTempSync('rmk Linux 打包 ');
    addTearDown(() => root.deleteSync(recursive: true));
    final bundle = Directory('${root.path}/bundle')..createSync();
    for (final file in ['Remlark', 'lib/libflutter_linux_gtk.so', 'lib/libapp.so']) {
      final target = File('${bundle.path}/$file');
      target.parent.createSync(recursive: true);
      target.writeAsStringSync('fixture');
    }
    final result = await Process.run('python3', [
      'linux/packaging/build.py',
      '--bundle',
      bundle.path,
      '--output',
      '${root.path}/output',
    ]);
    expect(result.exitCode, isNot(0));
    expect(result.stderr, contains('libremlark_rdp.so'));
    expect(Directory('${root.path}/output').existsSync(), isFalse);
  });
}
