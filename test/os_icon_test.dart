import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:remlark/modules/hosts/host_model.dart';
import 'package:remlark/modules/hosts/ui/os_icon.dart';
import 'package:remlark/modules/ssh/os_detector.dart';
import 'package:remlark/utils/os_registry.dart';

/// 构造不依赖数据库的图标测试主机。
HostEntry host({
  String? osId,
  HostProtocol protocol = HostProtocol.ssh,
  String name = 'test',
  Map<String, dynamic> extra = const {},
}) => HostEntry(
  uuid: 'icon-test',
  protocol: protocol,
  name: name,
  address: 'localhost',
  port: 22,
  osId: osId,
  extra: extra,
  createdAt: 0,
  updatedAt: 0,
);

/// 验证系统识别、资源完整性和不同协议下的图标优先级。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('全部已知系统保留自身身份，资源可解码且尺寸统一', () async {
    for (final id in OsRegistry.ids) {
      expect(OsDetector.normalizeId(id, 'debian rhel'), id);
      final bytes = await File(OsRegistry.assetFor(id)!).readAsBytes();
      final codec = await ui.instantiateImageCodec(bytes);
      final frame = await codec.getNextFrame();
      expect(frame.image.width, 256, reason: id);
      expect(frame.image.height, 256, reason: id);
      frame.image.dispose();
      codec.dispose();
    }
  });

  test('衍生发行版独立识别，别名兼容，父系统按完整标识和顺序匹配', () {
    expect(OsDetector.normalizeId('pop', 'ubuntu debian'), 'pop');
    expect(OsDetector.normalizeId('endeavouros', 'arch'), 'endeavouros');
    expect(OsDetector.normalizeId('OpenSUSE-Tumbleweed', ''), 'opensuse');
    expect(OsDetector.normalizeId('kylinserver', 'rhel'), 'kylin');
    expect(OsDetector.normalizeId('cbl-mariner', ''), 'azurelinux');
    expect(OsDetector.normalizeId('custom', 'ubuntu debian'), 'ubuntu');
    expect(OsDetector.normalizeId('custom', 'debian ubuntu'), 'debian');
    expect(OsDetector.normalizeId('custom', 'notdebian archlike'), 'custom');
    expect(OsDetector.normalizeId('', ''), 'linux');
    expect(OsDetector.parse('NetBSD\n')!.id, 'netbsd');
    expect(OsRegistry.assetFor('unknown'), isNull);
    expect(OsRegistry.inferFromLabel('PVE-Ubuntu'), 'ubuntu');
    expect(OsRegistry.inferFromLabel('Windows-Ubuntu'), isNull);
    expect(OsRegistry.inferFromLabel('ubuntu-server'), 'ubuntu');
    expect(OsRegistry.inferFromLabel('myubuntubox'), isNull);
  });

  testWidgets('RDP 使用实际系统图标，未知系统不默认显示 Windows', (tester) async {
    for (final brightness in Brightness.values) {
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(brightness: brightness),
          home: Row(
            children: [
              OsIcon(
                host: host(osId: 'ubuntu', protocol: HostProtocol.rdp),
                size: 20,
              ),
              OsIcon(host: host(protocol: HostProtocol.rdp)),
              OsIcon(
                host: host(protocol: HostProtocol.rdp, name: 'PVE-Ubuntu'),
              ),
              OsIcon(
                host: host(
                  osId: 'ubuntu',
                  protocol: HostProtocol.rdp,
                  extra: {'osOverride': 'windows'},
                ),
              ),
              OsIcon(host: host(osId: 'netbsd'), size: 48),
              OsIcon(host: host()),
              OsIcon(host: host(osId: 'unknown')),
            ],
          ),
        ),
      );
      final assets = tester
          .widgetList<Image>(find.byType(Image))
          .map((image) => (image.image as AssetImage).assetName);
      expect(assets, [
        'assets/os_icons/ubuntu.png',
        'assets/os_icons/ubuntu.png',
        'assets/os_icons/windows.png',
        'assets/os_icons/netbsd.png',
      ]);
      expect(tester.takeException(), isNull);
    }
  });
}
