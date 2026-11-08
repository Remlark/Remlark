// 多平台测试 P-31：SFTP 远程文件拖出到系统文件管理器（macOS file promise / Windows OLE 虚拟文件 / Linux 不支持）。
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:remlark/modules/sftp/sftp_service.dart';
import 'package:remlark/utils/file_drag_out/file_drag_out.dart';
import 'package:remlark/utils/file_drag_out/file_drag_out_macos.dart';
import 'package:remlark/utils/file_drag_out/file_drag_out_windows.dart';

import '../utils/source_text.dart';

const _channel = MethodChannel('remlark/file_drag');

FileEntry _file(String path, {bool isDir = false, int size = 0}) =>
    FileEntry(name: path.split('/').last, path: '/srv/$path', isDir: isDir, isLink: false, size: size);

/// 测试用拖出来源：目录 docs 下有两个文件（含子目录），记录取回请求
class _Source {
  final fetched = <(String remote, String local)>[];
  Object? failWith;

  DragOutSource build(List<FileEntry> items) => DragOutSource(
    items: items,
    walk: (dir) async => [
      (_file('docs/a.md', size: 3), 'docs/a.md'),
      (_file('docs/img/b.png', size: 5), 'docs/img/b.png'),
    ],
    fetch: (entry, localPath) async {
      if (failWith != null) throw failWith!;
      fetched.add((entry.path, localPath));
    },
  );
}

/// 拦截 start 调用，返回记录的参数
List<Map<Object?, Object?>> _mockStart(bool result) {
  final calls = <Map<Object?, Object?>>[];
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(_channel, (call) async {
    if (call.method == 'start') calls.add(call.arguments as Map<Object?, Object?>);
    return result;
  });
  return calls;
}

/// 模拟原生层调用 Dart（write / ended），返回解码后的结果或异常
Future<Object?> _nativeCall(String method, Map<String, Object?> args) async {
  const codec = StandardMethodCodec();
  final reply = await TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.handlePlatformMessage(
    'remlark/file_drag',
    codec.encodeMethodCall(MethodCall(method, args)),
    (_) {},
  );
  return codec.decodeEnvelope(reply!);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  tearDown(
    () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(_channel, null),
  );

  test('P-31 当前平台的实现：macOS / Windows 支持，Linux 不支持', () {
    final drag = FileDragOut.instance;
    if (Platform.isMacOS) {
      expect(drag, isA<MacFileDragOut>());
    } else if (Platform.isWindows) {
      expect(drag, isA<WindowsFileDragOut>());
    } else {
      expect(drag, isA<UnsupportedFileDragOut>());
    }
    expect(drag.supported, !Platform.isLinux);
  });

  test('P-31 不支持的平台不开始拖动', () async {
    expect(await UnsupportedFileDragOut().start(_Source().build([_file('a.txt')])), isFalse);
  });

  test('P-31 macOS 只交顶层项，Finder 放下后按序号取回到给定路径', () async {
    final calls = _mockStart(true);
    final src = _Source();
    final drag = MacFileDragOut();
    final ok = await drag.start(src.build([_file('docs', isDir: true), _file('x.log', size: 9)]));
    expect(ok, isTrue);
    expect(calls.single['entries'], [
      {'path': 'docs', 'isDir': true, 'size': 0},
      {'path': 'x.log', 'isDir': false, 'size': 9},
    ]);
    final session = calls.single['session'] as int;
    await _nativeCall('write', {'session': session, 'index': 0, 'path': '/Users/me/Desktop/docs 2'});
    expect(src.fetched, [('/srv/docs', '/Users/me/Desktop/docs 2')]);
    expect(await _nativeCall('ended', {'session': session}), isNull);
  });

  test('P-31 Windows 展开目录，父目录描述在子项之前', () async {
    final calls = _mockStart(true);
    final src = _Source();
    final drag = WindowsFileDragOut();
    expect(await drag.start(src.build([_file('docs', isDir: true), _file('x.log', size: 9)])), isTrue);
    final entries = (calls.single['entries'] as List).cast<Map<Object?, Object?>>();
    expect([for (final e in entries) (e['path'], e['isDir'], e['size'])], [
      ('docs', true, 0),
      ('docs/a.md', false, 3),
      ('docs/img', true, 0),
      ('docs/img/b.png', false, 5),
      ('x.log', false, 9),
    ]);
    // 资源管理器请求第 3 项（b.png）写入临时文件
    final session = calls.single['session'] as int;
    await _nativeCall('write', {'session': session, 'index': 3, 'path': r'C:\Temp\Remlark-drag\1\3\b.png'});
    expect(src.fetched, [('/srv/docs/img/b.png', r'C:\Temp\Remlark-drag\1\3\b.png')]);
  });

  test('P-31 取回失败、序号越界或会话过期时返回错误', () async {
    final calls = _mockStart(true);
    final src = _Source()..failWith = StateError('boom');
    final drag = MacFileDragOut();
    await drag.start(src.build([_file('x.log')]));
    final session = calls.single['session'] as int;
    expect(
      () => _nativeCall('write', {'session': session, 'index': 0, 'path': '/tmp/x.log'}),
      throwsA(isA<PlatformException>().having((e) => e.code, 'code', 'failed')),
    );
    expect(
      () => _nativeCall('write', {'session': session, 'index': 5, 'path': '/tmp/x.log'}),
      throwsA(isA<PlatformException>().having((e) => e.code, 'code', 'expired')),
    );
    expect(
      () => _nativeCall('write', {'session': session + 100, 'index': 0, 'path': '/tmp/x.log'}),
      throwsA(isA<PlatformException>().having((e) => e.code, 'code', 'expired')),
    );
  });

  test('P-31 原生层拒绝（鼠标已松开）或列目录失败时不算开始', () async {
    _mockStart(false);
    expect(await MacFileDragOut().start(_Source().build([_file('x.log')])), isFalse);
    _mockStart(true);
    final failing = DragOutSource(
      items: [_file('docs', isDir: true)],
      walk: (_) async => throw const SocketException('lost'),
      fetch: (_, _) async {},
    );
    expect(await WindowsFileDragOut().start(failing), isFalse);
    expect(await WindowsFileDragOut().start(_Source().build([])), isFalse);
  });

  test('P-31 原生实现注册同一通道并接入工程', () {
    const name = "'remlark/file_drag'";
    expect(readSourceText('lib/utils/file_drag_out/file_drag_out_channel.dart'), contains(name));
    expect(readSourceText('macos/Runner/FileDragSource.swift'), contains('"remlark/file_drag"'));
    expect(readSourceText('windows/runner/file_drag_source.cpp'), contains('"remlark/file_drag"'));
    // macOS：源文件加入 Xcode 工程并在主窗口挂接
    expect(readSourceText('macos/Runner.xcodeproj/project.pbxproj'), contains('FileDragSource.swift in Sources'));
    expect(readSourceText('macos/Runner/MainFlutterWindow.swift'), contains('FileDragSource.shared.attach'));
    // Windows：源文件加入 CMake、链接 shlwapi，并在 Flutter 窗口创建
    final cmake = readSourceText('windows/runner/CMakeLists.txt');
    expect(cmake, contains('"file_drag_source.cpp"'));
    expect(cmake, contains('shlwapi.lib'));
    expect(readSourceText('windows/runner/flutter_window.cpp'), contains('std::make_unique<FileDragSource>'));
    // Windows：放下后异步提取，结束后补发左键松开
    final cpp = readSourceText('windows/runner/file_drag_source.cpp');
    expect(cpp, contains('IDataObjectAsyncCapability'));
    expect(cpp, contains('WM_LBUTTONUP'));
  });
}
