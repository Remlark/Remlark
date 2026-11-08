import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:remlark/app/theme/app_palette.dart';
import 'package:remlark/app/theme/app_theme.dart';
import 'package:remlark/modules/sftp/file_kind.dart';
import 'package:remlark/modules/sftp/sftp_service.dart';
import 'package:remlark/modules/sftp/ui/file_type_icon.dart';

/// 构造测试用文件条目
FileEntry _file(String name, {bool isLink = false, bool isDir = false, String permissions = ''}) =>
    FileEntry(name: name, path: '/tmp/$name', isDir: isDir, isLink: isLink, size: 0, permissions: permissions);

void main() {
  group('FileKind.fromName', () {
    test('按扩展名识别常见类型，大小写不敏感', () {
      const cases = {
        'notes.txt': FileKind.text,
        'nginx.log': FileKind.text,
        'README.md': FileKind.markdown,
        'main.dart': FileKind.code,
        'App.TSX': FileKind.code,
        'deploy.sh': FileKind.script,
        'setup.ps1': FileKind.script,
        'index.html': FileKind.web,
        'docker-compose.yml': FileKind.config,
        'package.json': FileKind.config,
        'app.sqlite3': FileKind.database,
        'backup.sql': FileKind.database,
        'report.xlsx': FileKind.spreadsheet,
        'data.csv': FileKind.spreadsheet,
        'resume.docx': FileKind.document,
        'slides.pptx': FileKind.presentation,
        'manual.pdf': FileKind.pdf,
        'photo.JPG': FileKind.image,
        'song.flac': FileKind.audio,
        'movie.mkv': FileKind.video,
        'release.tar.gz': FileKind.archive,
        'files.7z': FileKind.archive,
        'nginx_1.24_amd64.deb': FileKind.package,
        'app.jar': FileKind.package,
        'ubuntu.iso': FileKind.diskImage,
        'disk.qcow2': FileKind.diskImage,
        'setup.exe': FileKind.executable,
        'libfoo.so': FileKind.executable,
        'server.key': FileKind.key,
        'id_ed25519.pub': FileKind.key,
        'Inter.woff2': FileKind.font,
      };
      cases.forEach((name, kind) => expect(FileKind.fromName(name), kind, reason: name));
    });

    test('识别惯用文件名与点文件', () {
      expect(FileKind.fromName('Makefile'), FileKind.code);
      expect(FileKind.fromName('Dockerfile'), FileKind.code);
      expect(FileKind.fromName('LICENSE'), FileKind.text);
      expect(FileKind.fromName('.bashrc'), FileKind.script);
      expect(FileKind.fromName('.gitignore'), FileKind.config);
      expect(FileKind.fromName('authorized_keys'), FileKind.key);
      expect(FileKind.fromName('id_rsa'), FileKind.key);
    });

    test('末尾数字段按去掉后的名称判断，无法识别时保持未知', () {
      expect(FileKind.fromName('syslog.1'), FileKind.generic);
      expect(FileKind.fromName('app.log.2'), FileKind.text);
      expect(FileKind.fromName('libssl.so.3'), FileKind.executable);
      expect(FileKind.fromName('python3.11'), FileKind.generic);
    });

    test('无扩展名、以点结尾或未知扩展名为普通文件', () {
      expect(FileKind.fromName('data'), FileKind.generic);
      expect(FileKind.fromName('weird.'), FileKind.generic);
      expect(FileKind.fromName('file.unknownext'), FileKind.generic);
      expect(FileKind.fromName('.hidden'), FileKind.generic);
    });
  });

  group('FileKind.of', () {
    test('符号链接优先于扩展名', () {
      expect(FileKind.of(_file('a.txt', isLink: true)), FileKind.symlink);
    });

    test('未识别但带执行位的文件为可执行文件，已识别类型不受执行位影响', () {
      expect(FileKind.of(_file('nginx', permissions: '-rwxr-xr-x')), FileKind.executable);
      expect(FileKind.of(_file('nginx', permissions: '-rw-r--r--')), FileKind.generic);
      expect(FileKind.of(_file('run.sh', permissions: '-rwxr-xr-x')), FileKind.script);
    });
  });

  test('同一扩展名只属于一个分类，且均为小写不含点', () {
    final seen = <String, FileKind>{};
    fileKindExtensions.forEach((kind, exts) {
      for (final ext in exts) {
        expect(ext, ext.toLowerCase());
        expect(ext.contains('.'), isFalse, reason: ext);
        expect(seen.containsKey(ext), isFalse, reason: '$ext 同时属于 ${seen[ext]} 和 $kind');
        seen[ext] = kind;
      }
    });
  });

  test('每个分类都有可解析的 SVG 资源', () async {
    TestWidgetsFlutterBinding.ensureInitialized();
    for (final kind in FileKind.values) {
      expect(File(kind.asset).existsSync(), isTrue, reason: kind.asset);
      // 通过 flutter_svg 实际解析，确保运行时不会因 SVG 语法问题显示空白
      final data = await rootBundle.loadString(kind.asset);
      final info = await vg.loadPicture(SvgStringLoader(data), null);
      info.picture.dispose();
    }
  });

  testWidgets('目录显示文件夹图标，文件显示 SVG', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.build(Brightness.dark, AccentPreset.values.first),
        home: Row(
          children: [FileTypeIcon.entry(_file('docs', isDir: true)), FileTypeIcon.entry(_file('a.pdf'))],
        ),
      ),
    );
    expect(find.byIcon(Icons.folder), findsOneWidget);
    expect(find.byType(SvgPicture), findsOneWidget);
  });
}
