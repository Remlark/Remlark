import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:remlark/data/database.dart';
import 'package:remlark/modules/settings/settings_repository.dart';
import 'package:remlark/modules/updates/github_release_client.dart';
import 'package:remlark/modules/updates/update_release.dart';
import 'package:remlark/modules/updates/update_service.dart';
import 'package:remlark/modules/updates/updates_controller.dart';
import 'package:remlark/utils/crypto_utils.dart';

/// 构造正式发布响应，不使用真实网络或用户凭据。
Map<String, dynamic> releaseJson({
  String version = 'v1.2.0',
  List<Map<String, dynamic>> assets = const [],
}) => {
  'tag_name': version,
  'draft': false,
  'prerelease': false,
  'body': 'Release notes',
  'assets': assets,
};

/// 创建可断言请求头的更新客户端。
UpdateService serviceWith(
  FutureOr<http.Response> Function(http.Request) handler, {
  Future<String?> Function()? credentials,
}) => UpdateService(
  client: GithubReleaseClient(
    inner: MockClient((request) async => handler(request)),
    credentials: credentials ?? () async => null,
  ),
);

/// 更新业务回归：鉴权边界、公开迁移、版本、校验、存储及手动下载。
void main() {
  test('语义版本比较忽略构建号，不提示降级，拒绝草稿/预发布/畸形版本', () {
    final release = UpdateRelease.fromJson(releaseJson());
    expect(release.newerThan('1.1.9+300'), isTrue);
    expect(release.newerThan('1.2.0+1'), isFalse);
    expect(release.newerThan('1.10.0'), isFalse);
    expect(release.newerThan('development'), isFalse);
    expect(release.newerThan('1.2.0-rc.2'), isTrue);
    for (final json in [
      releaseJson(version: 'broken'),
      releaseJson()..['draft'] = true,
      releaseJson()..['prerelease'] = true,
    ]) {
      expect(() => UpdateRelease.fromJson(json), throwsA(isA<UpdateFailure>()));
    }
  });

  test('公开仓库匿名检查，不调用本机 Git 凭据助手', () async {
    final service = serviceWith(
      (request) {
        expect(request.headers['Authorization'], isNull);
        return http.Response(jsonEncode(releaseJson()), 200);
      },
      credentials: () async =>
          throw StateError('public must not query credentials'),
    );
    expect((await service.latest()).version, '1.2.0');
    service.close();
  });

  test('私有仓库先匿名再鉴权，下载重定向不能携带 Token', () async {
    final calls = <http.Request>[];
    final service = serviceWith((request) {
      calls.add(request);
      if (request.url.host == 'release-assets.githubusercontent.com') {
        expect(request.headers['Authorization'], isNull);
        return http.Response('bytes', 200);
      }
      if (request.headers['Authorization'] == null) {
        return http.Response('', 404);
      }
      expect(request.headers['Authorization'], 'Bearer private-token');
      return http.Response(
        '',
        302,
        headers: {
          'location': 'https://release-assets.githubusercontent.com/payload?signature=abc',
        },
      );
    }, credentials: () async => 'private-token');
    final result = await service.client.get(
      Uri.parse('${GithubReleaseClient.apiRoot}assets/1'),
    );
    expect(result.body, 'bytes');
    expect(calls.length, 3);
    service.close();
  });

  test('阻止外站、HTTP、用户信息及非本仓库 API 的重定向', () async {
    for (final url in [
      'https://evil.example/file',
      'http://release-assets.githubusercontent.com/file',
      'https://token@github.com/Remlark/Remlark/releases/a',
      'https://api.github.com/repos/other/repo/releases/assets/1',
    ]) {
      var calls = 0;
      final service = serviceWith((_) {
        calls++;
        return http.Response('', 302, headers: {'location': url});
      });
      await expectLater(
        service.client.get(Uri.parse('${GithubReleaseClient.apiRoot}assets/1')),
        throwsA(isA<UpdateFailure>()),
      );
      expect(calls, 1);
      service.close();
    }
  });

  test('HTTP 错误使用固定文案，不暴露响应中的敏感内容', () async {
    for (final entry in {
      401: 'updates.error.token',
      403: 'updates.error.forbidden',
      404: 'updates.error.not_found',
      429: 'updates.error.forbidden',
      500: 'updates.error.network',
    }.entries) {
      final service = serviceWith(
        (_) => http.Response('sensitive-server-content', entry.key),
      );
      await expectLater(
        service.latest(),
        throwsA(isA<UpdateFailure>().having((e) => e.key, 'key', entry.value)),
      );
      service.close();
    }
  });

  test('下载验证 digest，失败不覆盖旧文件，临时文件清理', () async {
    final dir = await Directory.systemTemp.createTemp('remlark-update-test-');
    addTearDown(() => dir.delete(recursive: true));
    final payload = utf8.encode('installer-payload');
    final hash = (await CryptoUtils.sha256(payload))
        .map((b) => b.toRadixString(16).padLeft(2, '0'))
        .join();
    final service = serviceWith((_) => http.Response.bytes(payload, 200));
    final output = File('${dir.path}/installer');
    await output.writeAsString('old');
    final bad = UpdateAsset(
      1,
      'installer',
      payload.length,
      'sha256:${'0' * 64}',
    );
    await expectLater(
      service.download(
        UpdateRelease('1.2.0', '', [bad]),
        bad,
        output.path,
        (_, _) {},
      ),
      throwsA(isA<UpdateFailure>()),
    );
    expect(await output.readAsString(), 'old');
    final good = UpdateAsset(1, 'installer', payload.length, 'sha256:$hash');
    await service.download(
      UpdateRelease('1.2.0', '', [good]),
      good,
      output.path,
      (_, _) {},
    );
    expect(await output.readAsBytes(), payload);
    expect(await dir.list().length, 1);
    service.close();
  });

  test('旧 Release 缺少 digest 时从 SHA256SUMS 校验，缺少清单拒绝交付', () async {
    final dir = await Directory.systemTemp.createTemp('remlark-update-sums-');
    addTearDown(() => dir.delete(recursive: true));
    final payload = utf8.encode('verified');
    final hash = (await CryptoUtils.sha256(payload))
        .map((b) => b.toRadixString(16).padLeft(2, '0'))
        .join();
    final service = serviceWith(
      (r) => r.url.path.endsWith('/2')
          ? http.Response('$hash  installer\n', 200)
          : http.Response.bytes(payload, 200),
    );
    final asset = UpdateAsset(1, 'installer', payload.length, null);
    const sums = UpdateAsset(2, 'SHA256SUMS', 100, null);
    final output = '${dir.path}/installer';
    await service.download(
      UpdateRelease('1.2.0', '', [asset, sums]),
      asset,
      output,
      (_, _) {},
    );
    expect(await File(output).readAsBytes(), payload);
    await expectLater(
      service.download(
        UpdateRelease('1.2.0', '', [asset]),
        asset,
        output,
        (_, _) {},
      ),
      throwsA(isA<UpdateFailure>()),
    );
    expect(await File(output).readAsBytes(), payload);
    service.close();
  });

  test('下载流中断时清理临时文件且不覆盖已有安装包', () async {
    final dir = await Directory.systemTemp.createTemp(
      'remlark-update-interrupted-',
    );
    addTearDown(() => dir.delete(recursive: true));
    final output = File('${dir.path}/installer');
    await output.writeAsString('previous');
    final client = GithubReleaseClient(
      inner: MockClient.streaming((request, body) async {
        return http.StreamedResponse(
          Stream<List<int>>.error(const SocketException('disconnected')),
          200,
        );
      }),
    );
    final service = UpdateService(client: client);
    final asset = UpdateAsset(1, 'installer', 100, 'sha256:${'0' * 64}');
    await expectLater(
      service.download(
        UpdateRelease('1.2.0', '', [asset]),
        asset,
        output.path,
        (_, _) {},
      ),
      throwsA(isA<SocketException>()),
    );
    expect(await output.readAsString(), 'previous');
    expect(await dir.list().length, 1);
    service.close();
  });

  test('迁移时移除旧 Token 配置，检查只读取版本不下载', () async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    final repo = SettingsRepository(db);
    await repo.set('updates.github_token', 'old-encrypted-token');
    final controller = UpdatesController(
      repo,
      service: serviceWith((r) {
        expect(r.url.path.endsWith('/latest'), isTrue);
        return http.Response(jsonEncode(releaseJson()), 200);
      }),
      currentVersion: '1.0.0+1',
    );
    await controller.load();
    expect(await repo.get('updates.github_token'), isNull);
    await controller.check();
    expect(controller.hasUpdate, isTrue);
    controller.dispose();
  });

  test('自动检查开关持久化，关闭时不请求，开启仅查询不下载', () async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    final repo = SettingsRepository(db);
    await repo.set('updates.automatic', 'false');
    var calls = 0;
    final service = serviceWith((request) {
      expect(request.url.path.endsWith('/latest'), isTrue);
      calls++;
      return http.Response(jsonEncode(releaseJson()), 200);
    });
    final controller = UpdatesController(repo, service: service);
    await controller.load();
    controller.start();
    await Future<void>.delayed(Duration.zero);
    expect(calls, 0);
    await controller.setAutomatic(true);
    await Future<void>.delayed(Duration.zero);
    expect(calls, 1);
    expect(await repo.get('updates.automatic'), 'true');
    await controller.setAutomatic(false);
    controller.start();
    await Future<void>.delayed(Duration.zero);
    expect(calls, 1);
    expect(await repo.get('updates.automatic'), 'false');
    controller.dispose();
  });

  test('并发检查合并，失败保留旧结果和成功时间，短期失败不重复联网', () async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    final gate = Completer<void>();
    var calls = 0;
    var fail = false;
    final service = serviceWith((_) async {
      calls++;
      await gate.future;
      return fail
          ? http.Response('', 500)
          : http.Response(jsonEncode(releaseJson()), 200);
    });
    final c = UpdatesController(
      SettingsRepository(db),
      service: service,
      currentVersion: '1.0.0',
    );
    final first = c.check();
    await c.check();
    gate.complete();
    await first;
    expect(calls, 1);
    final checkedAt = c.checkedAt;
    fail = true;
    await c.check();
    expect(c.hasUpdate, isTrue);
    expect(c.checkedAt, checkedAt);
    expect(c.error, 'updates.error.network');
    await c.check();
    expect(calls, 2);
    c.dispose();
  });
}
