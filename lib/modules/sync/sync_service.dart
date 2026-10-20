import 'dart:async';
import 'dart:convert';

import 'package:cryptography/cryptography.dart' show SecretBoxAuthenticationError;
import 'package:flutter/foundation.dart';

import '../../utils/app_log.dart';
import '../../utils/crypto_utils.dart';
import '../../utils/secret_store.dart';
import '../hosts/group_repository.dart';
import '../hosts/host_model.dart';
import '../hosts/host_repository.dart';
import '../keys/key_model.dart';
import '../keys/key_repository.dart';
import '../settings/settings_repository.dart';
import 'sync_api.dart';
import 'sync_config.dart';

/// 同步结果统计
class SyncReport {
  int pushed = 0;
  int pulled = 0;
  int unchanged = 0;
  int detached = 0;
}

/// 同步服务。规则：
/// - 每台主机有唯一 uuid，以 uuid 对应的“最后更新时间”决定方向：本地新则上传，服务器新则下载
/// - 主机的 syncedAt 记录最后一次与服务器一致时的时间，与 updatedAt 相等即为“已同步”
/// - 服务器上存在而本地没有的主机会被拉取到本地
/// - 从服务器删除后留下删除标记，各客户端将该主机改为“仅本地”，不再同步
/// - 载荷在客户端使用口令派生的密钥做 AES-GCM 加密，服务器只保存密文
/// - 未配置同步服务器时不影响任何本地功能
class SyncService extends ChangeNotifier {
  SyncService(this._settings, this._hosts, this._groups, this._keys);

  final SettingsRepository _settings;
  final HostRepository _hosts;
  final GroupRepository _groups;
  final KeyRepository _keys;

  SyncConfig config = const SyncConfig();
  bool syncing = false;
  String? lastError;
  SyncReport? lastReport;
  Timer? _timer;
  Uint8List? _key;
  String? _keyFor;

  /// 主机同步状态变化时回调（刷新主机列表）
  VoidCallback? onHostsChanged;

  static const _cfgKey = 'sync.config';

  /// 加载配置并启动自动同步
  Future<void> load() async {
    final j = await _settings.getJson(_cfgKey);
    config = SyncConfig(
      serverUrl: j['serverUrl'] as String? ?? '',
      token: await SecretStore.instance.open(j['token'] as String?) ?? '',
      passphrase: await SecretStore.instance.open(j['passphrase'] as String?) ?? '',
      intervalMinutes: (j['interval'] as num?)?.toInt() ?? 0,
      lastSyncAt: (j['lastSyncAt'] as num?)?.toInt(),
    );
    _schedule();
    notifyListeners();
  }

  /// 保存配置
  Future<void> saveConfig(SyncConfig c) async {
    config = c;
    _key = null;
    await _settings.setJson(_cfgKey, {
      'serverUrl': c.serverUrl.trim(),
      'token': await SecretStore.instance.seal(c.token),
      'passphrase': await SecretStore.instance.seal(c.passphrase),
      'interval': c.intervalMinutes,
      if (c.lastSyncAt != null) 'lastSyncAt': c.lastSyncAt,
    });
    _schedule();
    notifyListeners();
  }

  void _schedule() {
    _timer?.cancel();
    if (config.isConfigured && config.intervalMinutes > 0) {
      _timer = Timer.periodic(Duration(minutes: config.intervalMinutes), (_) {
        syncNow().catchError((_) => SyncReport());
      });
    }
  }

  SyncApi get _api => SyncApi(config.serverUrl, config.token);

  /// 派生加密密钥（盐由令牌决定，同一数据空间内各客户端一致）
  Future<Uint8List> _cryptoKey() async {
    final id = '${config.token}\u0000${config.passphrase}';
    if (_key != null && _keyFor == id) return _key!;
    final salt = await CryptoUtils.sha256(utf8.encode('remlark-sync:${config.token}'));
    _key = await CryptoUtils.deriveKey(config.passphrase, salt);
    _keyFor = id;
    return _key!;
  }

  /// 测试连接
  Future<void> testConnection(SyncConfig c) => SyncApi(c.serverUrl, c.token).ping();

  /// 构造主机的加密载荷
  Future<String> _encode(HostEntry h) async {
    String? groupName;
    if (h.groupUuid != null) {
      for (final g in await _groups.list()) {
        if (g.uuid == h.groupUuid) groupName = g.name;
      }
    }
    final key = h.keyUuid == null ? null : await _keys.get(h.keyUuid!);
    final payload = jsonEncode({'host': h.toPortableJson(), 'group': ?groupName, 'key': ?key?.toJson()});
    return CryptoUtils.encryptString(await _cryptoKey(), payload);
  }

  /// 解密载荷并写入本地
  Future<void> _apply(String cipher, int remoteUpdatedAt) async {
    final plain = await CryptoUtils.decryptString(await _cryptoKey(), cipher);
    final j = jsonDecode(plain) as Map<String, dynamic>;
    final keyJson = j['key'] as Map<String, dynamic>?;
    if (keyJson != null) await _keys.save(KeyEntry.fromJson(keyJson));
    var host = HostEntry.fromPortableJson(j['host'] as Map<String, dynamic>);
    final groupName = j['group'] as String?;
    String? groupUuid;
    if (groupName != null) groupUuid = (await _groups.ensureByName(groupName)).uuid;
    final local = await _hosts.getByUuid(host.uuid);
    host = host.copyWith(
      groupUuid: () => groupUuid,
      updatedAt: remoteUpdatedAt,
      syncEnabled: true,
      syncedAt: () => remoteUpdatedAt,
      // 本机专属信息保留本地值
      hostKeyFingerprint: () => local?.hostKeyFingerprint,
      lastConnectedAt: () => local?.lastConnectedAt,
      osId: () => host.osId ?? local?.osId,
      osName: () => host.osName ?? local?.osName,
    );
    await _hosts.save(host, touch: false);
  }

  /// 上传一台主机
  Future<bool> _push(HostEntry h) async {
    final ok = await _api.put(h.uuid, h.updatedAt, await _encode(h));
    if (ok) await _hosts.setSyncState(h.uuid, enabled: true, syncedAt: h.updatedAt);
    return ok;
  }

  /// 立即同步
  Future<SyncReport> syncNow() async {
    if (!config.isConfigured) throw StateError('sync not configured');
    if (syncing) return lastReport ?? SyncReport();
    syncing = true;
    lastError = null;
    notifyListeners();
    final report = SyncReport();
    final sw = Stopwatch()..start();
    AppLog.i('sync', '开始同步');
    try {
      final remote = await _api.index();
      final locals = await _hosts.listSyncEnabled();
      final localIds = <String>{};
      final toPull = <String, int>{};
      for (final l in locals) {
        localIds.add(l.uuid);
        final r = remote[l.uuid];
        if (r == null) {
          await _push(l);
          report.pushed++;
        } else if (r.deleted) {
          await _hosts.setSyncState(l.uuid, enabled: false, syncedAt: null);
          report.detached++;
        } else if (r.updatedAt == l.updatedAt) {
          if (l.syncedAt != l.updatedAt) {
            await _hosts.setSyncState(l.uuid, enabled: true, syncedAt: l.updatedAt);
          }
          report.unchanged++;
        } else if (l.updatedAt > r.updatedAt) {
          if (await _push(l)) {
            report.pushed++;
          } else {
            toPull[l.uuid] = r.updatedAt;
          }
        } else {
          toPull[l.uuid] = r.updatedAt;
        }
      }
      // 服务器有、本地未参与同步或不存在的主机
      for (final r in remote.values) {
        if (r.deleted || localIds.contains(r.uuid)) continue;
        final local = await _hosts.getByUuid(r.uuid);
        if (local != null && local.updatedAt > r.updatedAt) {
          await _push(local.copyWith(syncEnabled: true));
          report.pushed++;
        } else {
          toPull[r.uuid] = r.updatedAt;
        }
      }
      if (toPull.isNotEmpty) {
        final payloads = await _api.fetch(toPull.keys.toList());
        for (final e in payloads.entries) {
          await _apply(e.value, toPull[e.key]!);
          report.pulled++;
        }
      }
      lastReport = report;
      AppLog.i(
        'sync',
        '同步完成 ${sw.elapsedMilliseconds}ms：推送 ${report.pushed}，拉取 ${report.pulled}，'
            '未变 ${report.unchanged}，解除 ${report.detached}',
      );
      await saveConfig(config.copyWith(lastSyncAt: DateTime.now().millisecondsSinceEpoch));
    } catch (e, st) {
      lastError = e is SecretBoxAuthenticationError ? 'sync.error.passphrase' : '$e';
      AppLog.e('sync', '同步失败', e, st);
      rethrow;
    } finally {
      syncing = false;
      onHostsChanged?.call();
      notifyListeners();
    }
    return report;
  }

  /// 加入同步：标记后立即上传（服务器不可用时等待下次同步）
  Future<void> enable(HostEntry h) async {
    await _hosts.setSyncState(h.uuid, enabled: true, syncedAt: null);
    onHostsChanged?.call();
    if (!config.isConfigured) return;
    try {
      final fresh = await _hosts.getByUuid(h.uuid);
      if (fresh != null) await _push(fresh);
    } catch (_) {}
    onHostsChanged?.call();
  }

  /// 从同步服务器删除该主机，之后不再同步（本地保留）
  Future<void> removeFromServer(String uuid) async {
    if (config.isConfigured) await _api.delete(uuid);
    await _hosts.setSyncState(uuid, enabled: false, syncedAt: null);
    onHostsChanged?.call();
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }
}
