import 'dart:io';

/// 复制版本工具和发布脚本，供多平台测试在隔离目录中使用不同的 VERSION。
Directory createVersionFixture(String version) {
  final root = Directory.systemTemp.createTempSync('remlark version 中文 ');
  for (final path in [
    'tools/utils/app_version.py',
    'tools/release/prepare.py',
  ]) {
    final target = File('${root.path}/$path');
    target.parent.createSync(recursive: true);
    File(path).copySync(target.path);
  }
  File('${root.path}/VERSION').writeAsStringSync(version);
  // 故意不同，确认所有工具都不回退到 pubspec 版本。
  File('${root.path}/pubspec.yaml')
      .writeAsStringSync('name: fixture\nversion: 9.9.9+9\n');
  return root;
}
