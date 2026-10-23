import 'dart:io';
import 'dart:async';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:remlark/app/app.dart';
import 'package:remlark/app/app_services.dart';
import 'package:remlark/app/nav_controller.dart';
import 'package:remlark/data/database.dart';
import 'package:remlark/l10n/app_localizations.dart';
import 'package:remlark/modules/hosts/host_model.dart';
import 'package:remlark/modules/hosts/ui/host_editor_dialog.dart';
import 'package:remlark/modules/proxies/proxy_profile.dart';
import 'package:remlark/modules/proxies/proxy_connection_test.dart';
import 'package:remlark/utils/network_endpoint.dart';
import 'package:remlark/modules/proxies/ui/host_proxy_selector.dart';
import 'package:remlark/modules/proxies/ui/proxy_editor_dialog.dart';
import 'package:remlark/modules/proxies/ui/proxy_settings_section.dart';
import 'package:remlark/utils/crypto_utils.dart';
import 'package:remlark/utils/secret_store.dart';
import 'package:remlark/utils/ui_utils.dart';

import 'helpers/test_fonts.dart';

/// 可控检测替身：不访问外网，验证测试结果与保存行为相互独立。
class _FakeConnectionTest implements ProxyConnectionTest {
  Completer<ProxyTestResult>? pending;
  int calls = 0;
  int cancellations = 0;

  /// 保留检测请求，由测试显式决定结束时机。
  @override
  Future<ProxyTestResult> check(ProxyConfig config, NetworkEndpoint target) {
    calls++;
    pending = Completer<ProxyTestResult>();
    return pending!.future;
  }

  /// 提交可控结果。
  void finish(ProxyTestStatus status) {
    final request = pending;
    pending = null;
    request?.complete(
      ProxyTestResult(status, const Duration(milliseconds: 32)),
    );
  }

  /// 取消时完成旧请求，模拟真实连接被释放。
  @override
  void cancel() {
    cancellations++;
    finish(ProxyTestStatus.cancelled);
  }
}

/// 创建与实际应用相同的依赖和页面，使用独立内存数据库。
Future<AppServices> _start(WidgetTester tester, {bool seed = true}) async {
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  tester.view.devicePixelRatio = 1;
  if (tester.view.physicalSize.width < 960) {
    tester.view.physicalSize = const Size(1200, 900);
  }
  SecretStore.initForTest(CryptoUtils.randomBytes(32));
  await tester.runAsync(loadTestFonts);
  final services = AppServices(AppDatabase(NativeDatabase.memory()));
  addTearDown(services.db.close);
  await tester.runAsync(() async {
    await services.init(installKeySnippetName: 'Key');
    await services.settings.setThemeMode(ThemeMode.light);
    await services.settings.setLocale(const Locale('zh'));
    if (seed) {
      for (final entry in [
        const ProxyEntry(
          uuid: 'hk',
          name: '香港出口',
          config: ProxyConfig(
            type: ProxyType.socks5,
            host: 'proxy-hk.example.com',
            port: 1080,
            username: 'proxy-user',
            password: 'secret',
          ),
        ),
        const ProxyEntry(
          uuid: 'office',
          name: '办公网关',
          config: ProxyConfig(
            type: ProxyType.http,
            host: 'proxy.corp.example.com',
            port: 8080,
          ),
        ),
        const ProxyEntry(
          uuid: 'local',
          name: '本地代理',
          config: ProxyConfig(
            type: ProxyType.socks5,
            host: '127.0.0.1',
            port: 7890,
          ),
        ),
      ]) {
        await services.proxyRepo.save(entry);
      }
      for (var i = 0; i < 8; i++) {
        await services.hostRepo.save(
          HostEntry(
            uuid: 'host-$i',
            name: 'Host $i',
            protocol: HostProtocol.ssh,
            address: '192.0.2.1',
            port: 22,
            proxyUuid: 'hk',
            createdAt: 1,
            updatedAt: 1,
          ),
        );
      }
      await services.hosts.load();
      await services.proxies.load();
    }
  });
  await tester.pumpWidget(
    RepaintBoundary(
      key: const ValueKey('proxy-preview'),
      child: RemlarkApp(services: services),
    ),
  );
  UiUtils.navigatorKey.currentContext!.read<NavController>().goSettings(
    SettingsSection.proxies,
  );
  await _settle(tester);
  return services;
}

/// 允许 ORM 异步任务结束，再等待页面动画完成。
Future<void> _settle(WidgetTester tester) async {
  await tester.runAsync(
    () => Future<void>.delayed(const Duration(milliseconds: 100)),
  );
  await tester.pumpAndSettle();
}

/// 覆盖编辑弹窗、服务器选择、内嵌管理及多语言布局。
void main() {
  testWidgets('连接测试失败或测试目标无效仍可保存代理', (tester) async {
    final services = await _start(tester, seed: false);
    final connectionTest = _FakeConnectionTest();
    showDialog<void>(
      context: UiUtils.navigatorKey.currentContext!,
      builder: (_) => ProxyEditorDialog(
        controller: services.proxies,
        connectionTest: connectionTest,
      ),
    );
    await _settle(tester);
    await tester.enterText(
      find.byKey(const ValueKey('proxy-name')),
      'Test proxy',
    );
    await tester.enterText(
      find.byKey(const ValueKey('proxy-host')),
      '127.0.0.1',
    );
    await tester.enterText(find.byKey(const ValueKey('proxy-port')), '1087');
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('测试连接'));
    await tester.tap(find.text('测试连接'));
    await tester.pump();
    expect(connectionTest.calls, 1);
    connectionTest.finish(ProxyTestStatus.timeout);
    await tester.pumpAndSettle();
    expect(find.text('连接超时，仍可保存。'), findsOneWidget);
    await tester.enterText(
      find.byKey(const ValueKey('proxy-test-target')),
      'invalid',
    );
    await tester.tap(find.text('测试连接'));
    await tester.pumpAndSettle();
    expect(find.text('请输入主机:端口，IPv6 使用 [地址]:端口'), findsOneWidget);
    expect(
      tester
          .widget<FilledButton>(find.widgetWithText(FilledButton, '保存'))
          .onPressed,
      isNotNull,
    );
    await tester.tap(find.widgetWithText(FilledButton, '保存'));
    await _settle(tester);
    expect(services.proxies.entries, hasLength(1));
    expect(find.byType(ProxyEditorDialog), findsNothing);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('修改参数使旧测试结果失效，测试进行中仍可保存并取消连接', (tester) async {
    final services = await _start(tester);
    final connectionTest = _FakeConnectionTest();
    final existing = services.proxies.entries.firstWhere((e) => e.uuid == 'hk');
    showDialog<void>(
      context: UiUtils.navigatorKey.currentContext!,
      builder: (_) => ProxyEditorDialog(
        controller: services.proxies,
        existing: existing,
        connectionTest: connectionTest,
      ),
    );
    await _settle(tester);
    await tester.ensureVisible(find.text('测试连接'));
    await tester.tap(find.text('测试连接'));
    await tester.pump();
    connectionTest.finish(ProxyTestStatus.success);
    await tester.pumpAndSettle();
    expect(find.text('连接成功 · 32 ms'), findsOneWidget);
    await tester.enterText(find.byKey(const ValueKey('proxy-port')), '1081');
    await tester.pumpAndSettle();
    expect(find.text('连接成功 · 32 ms'), findsNothing);
    await tester.ensureVisible(find.text('测试连接'));
    await tester.tap(find.text('测试连接'));
    await tester.pump();
    expect(find.text('正在测试连接…'), findsOneWidget);
    final cancellations = connectionTest.cancellations;
    await tester.tap(find.widgetWithText(FilledButton, '保存'));
    await _settle(tester);
    expect(find.byType(ProxyEditorDialog), findsNothing);
    expect(connectionTest.cancellations, greaterThan(cancellations));
    expect(
      services.proxies.entries.firstWhere((e) => e.uuid == 'hk').config.port,
      1081,
    );
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('管理弹窗单条数据自然收缩，多条数据内部滚动且搜索和关闭始终可见', (tester) async {
    final services = await _start(tester, seed: false);
    tester.view.physicalSize = const Size(960, 640);
    await tester.runAsync(
      () => services.proxies.save(
        const ProxyEntry(
          uuid: 'single',
          name: 'proxy',
          config: ProxyConfig(
            type: ProxyType.socks5,
            host: '127.0.0.1',
            port: 1087,
          ),
        ),
      ),
    );
    ProxySettingsSection.showManager(UiUtils.navigatorKey.currentContext!);
    await _settle(tester);
    final content = find.byKey(const ValueKey('proxy-manager-content'));
    final singleHeight = tester.getSize(content).height;
    expect(singleHeight, lessThan(190));
    final field = find.descendant(
      of: content,
      matching: find.byType(TextField),
    );
    final add = find.descendant(
      of: content,
      matching: find.widgetWithText(FilledButton, '添加代理'),
    );
    expect(
      (tester.getCenter(field).dy - tester.getCenter(add).dy).abs(),
      lessThan(3),
    );
    await tester.runAsync(() async {
      for (var i = 0; i < 20; i++) {
        await services.proxies.save(
          ProxyEntry(
            uuid: 'proxy-$i',
            name: 'Proxy $i',
            config: const ProxyConfig(
              type: ProxyType.http,
              host: 'office.example.com',
              port: 8080,
            ),
          ),
        );
      }
    });
    await _settle(tester);
    expect(tester.getSize(content).height, greaterThan(singleHeight + 150));
    expect(tester.getSize(content).height, lessThan(480));
    final close = find.widgetWithText(OutlinedButton, '关闭');
    final closeBefore = tester.getRect(close);
    await tester.drag(
      find.descendant(of: content, matching: find.byType(ListView)),
      const Offset(0, -400),
    );
    await tester.pumpAndSettle();
    expect(tester.getRect(close), closeBefore);
    expect(field.hitTestable(), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });
  testWidgets('新增代理验证必填与端口，取消不保存，成功保存后列表可搜索', (tester) async {
    final services = await _start(tester, seed: false);
    await tester.tap(find.text('添加代理'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();
    expect(find.text('请填写此项'), findsNWidgets(2));
    await tester.enterText(find.byKey(const ValueKey('proxy-name')), 'Office');
    await tester.enterText(
      find.byKey(const ValueKey('proxy-host')),
      'proxy.example.com',
    );
    await tester.enterText(find.byKey(const ValueKey('proxy-port')), '99999');
    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();
    expect(services.proxies.entries, isEmpty);
    await tester.enterText(find.byKey(const ValueKey('proxy-port')), '8080');
    await tester.enterText(
      find.byKey(const ValueKey('proxy-password')),
      'private-password',
    );
    await tester.tap(find.text('保存'));
    await _settle(tester);
    expect(find.byType(ProxyEditorDialog), findsNothing);
    expect(services.proxies.entries.single.config.password, 'private-password');
    expect(find.text('Office'), findsOneWidget);
    await tester.enterText(find.byType(TextField).first, 'no-such-proxy');
    await tester.pumpAndSettle();
    expect(find.text('没有匹配的代理服务器。'), findsOneWidget);
    await tester.enterText(find.byType(TextField).first, '');
    await tester.pumpAndSettle();
    await tester.tap(find.text('添加代理'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('proxy-name')),
      'Cancelled',
    );
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    expect(services.proxies.entries, hasLength(1));
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('主机选择代理保留草稿，管理弹窗关闭后仍在原表单，取消主机不写入引用', (tester) async {
    final services = await _start(tester);
    final original = services.hosts.all.first;
    HostEditorDialog.show(
      UiUtils.navigatorKey.currentContext!,
      existing: original,
    );
    await _settle(tester);
    await tester.tap(find.text('跳板与代理'));
    await _settle(tester);
    final selector = tester.widget<HostProxySelector>(
      find.byType(HostProxySelector),
    );
    final form = selector.form;
    expect(form.proxyUuid, 'hk');
    await tester.ensureVisible(
      find.descendant(
        of: find.byType(DropdownMenu<String>),
        matching: find.byType(TextField),
      ),
    );
    await tester.tap(
      find.descendant(
        of: find.byType(DropdownMenu<String>),
        matching: find.byType(TextField),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('不使用代理（直接连接）').last);
    await tester.pumpAndSettle();
    expect(form.proxyUuid, isNull);
    expect(form.build().proxy.enabled, isFalse);
    await tester.ensureVisible(
      find.descendant(
        of: find.byType(DropdownMenu<String>),
        matching: find.byType(TextField),
      ),
    );
    await tester.tap(
      find.descendant(
        of: find.byType(DropdownMenu<String>),
        matching: find.byType(TextField),
      ),
    );
    await tester.pumpAndSettle();
    await tester.enterText(
      find.descendant(
        of: find.byType(DropdownMenu<String>),
        matching: find.byType(TextField),
      ),
      '办公',
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('办公网关').last);
    await tester.pumpAndSettle();
    expect(form.proxyUuid, 'office');
    expect(form.build().proxy.type, ProxyType.http);
    await tester.ensureVisible(find.text('管理代理'));
    await tester.tap(find.text('管理代理'));
    await _settle(tester);
    expect(find.byType(ProxySettingsSection), findsNWidgets(2));
    await tester.tap(find.widgetWithText(OutlinedButton, '关闭'));
    await tester.pumpAndSettle();
    expect(find.byType(HostEditorDialog), findsOneWidget);
    expect(
      identical(
        tester.widget<HostProxySelector>(find.byType(HostProxySelector)).form,
        form,
      ),
      isTrue,
    );
    await tester.tap(find.widgetWithText(OutlinedButton, '取消'));
    await tester.pumpAndSettle();
    final saved = await tester.runAsync(
      () => services.hostRepo.getByUuid(original.uuid),
    );
    expect(saved!.proxyUuid, 'hk');
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('中英文、明暗主题及最小桌面窗口下设置列表和编辑弹窗无溢出', (tester) async {
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    tester.view.devicePixelRatio = 1;
    final services = await _start(tester);
    for (final locale in ['zh', 'en']) {
      for (final mode in [ThemeMode.light, ThemeMode.dark]) {
        await tester.runAsync(() async {
          await services.settings.setLocale(Locale(locale));
          await services.settings.setThemeMode(mode);
        });
        for (final size in [const Size(960, 640), const Size(1440, 1024)]) {
          tester.view.physicalSize = size;
          await _settle(tester);
          await tester.tap(find.text(S(Locale(locale)).t('proxy.add')));
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull, reason: '$locale $mode $size');
          await tester.tap(find.text(S(Locale(locale)).t('common.cancel')));
          await tester.pumpAndSettle();
        }
      }
    }
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets(
    '方案一代理设置与编辑弹窗原生截图',
    (tester) async {
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(1440, 1024);
      final services = await _start(tester);
      await expectLater(
        find.byKey(const ValueKey('proxy-preview')),
        matchesGoldenFile(
          '../build/validation/proxy-design/implemented-settings.png',
        ),
      );
      await tester.tap(find.text('香港出口'));
      await tester.pumpAndSettle();
      await expectLater(
        find.byKey(const ValueKey('proxy-preview')),
        matchesGoldenFile(
          '../build/validation/proxy-design/implemented-dialog.png',
        ),
      );
      expect(services.proxies.usage['hk'], 8);
      await tester.tap(find.widgetWithText(OutlinedButton, '取消'));
      await tester.pumpAndSettle();
      HostEditorDialog.show(
        UiUtils.navigatorKey.currentContext!,
        existing: services.hosts.all.first,
      );
      await _settle(tester);
      await tester.tap(find.text('跳板与代理'));
      await _settle(tester);
      await tester.ensureVisible(find.byType(HostProxySelector));
      await tester.pumpAndSettle();
      await expectLater(
        find.byKey(const ValueKey('proxy-preview')),
        matchesGoldenFile(
          '../build/validation/proxy-design/implemented-host-selector.png',
        ),
      );
      await tester.pumpWidget(const SizedBox.shrink());
    },
    skip: Platform.environment['PROXY_SNAPSHOT'] != '1',
    variant: TargetPlatformVariant.only(TargetPlatform.macOS),
  );

  testWidgets(
    '方案二紧凑管理弹窗及可选测试失败状态截图',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(1024, 768);
      final services = await _start(tester, seed: false);
      const entry = ProxyEntry(
        uuid: 'single',
        name: 'proxy',
        config: ProxyConfig(
          type: ProxyType.socks5,
          host: '127.0.0.1',
          port: 1087,
        ),
      );
      await tester.runAsync(() => services.proxies.save(entry));
      ProxySettingsSection.showManager(UiUtils.navigatorKey.currentContext!);
      await _settle(tester);
      await expectLater(
        find.byKey(const ValueKey('proxy-preview')),
        matchesGoldenFile(
          '../build/validation/proxy-design/manager-single.png',
        ),
      );
      await tester.tap(find.widgetWithText(OutlinedButton, '关闭'));
      await tester.pumpAndSettle();
      tester.view.physicalSize = const Size(1200, 900);
      await tester.pumpAndSettle();
      final connectionTest = _FakeConnectionTest();
      showDialog<void>(
        context: UiUtils.navigatorKey.currentContext!,
        builder: (_) => ProxyEditorDialog(
          controller: services.proxies,
          existing: entry,
          connectionTest: connectionTest,
        ),
      );
      await _settle(tester);
      await tester.tap(find.text('测试连接'));
      await tester.pump();
      connectionTest.finish(ProxyTestStatus.connection);
      await tester.pumpAndSettle();
      await expectLater(
        find.byKey(const ValueKey('proxy-preview')),
        matchesGoldenFile(
          '../build/validation/proxy-design/editor-test-failed.png',
        ),
      );
      expect(
        tester
            .widget<FilledButton>(find.widgetWithText(FilledButton, '保存'))
            .onPressed,
        isNotNull,
      );
      await tester.pumpWidget(const SizedBox.shrink());
    },
    skip: Platform.environment['PROXY_SNAPSHOT'] != '1',
    variant: TargetPlatformVariant.only(TargetPlatform.macOS),
  );
}
