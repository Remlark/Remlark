import 'dart:async';
import 'dart:convert';

import 'package:cryptography/cryptography.dart'
    show SecretBoxAuthenticationError;
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
import 'host_sync_bundle.dart';
import 'sync_api.dart';
import 'sync_config.dart';

/// 同步结果统计
class SyncReport {
  int pushed = 0;
  int pulled = 0;
  int unchanged = 0;
  int detached = 0;
}

/// 单轮同步固定使用的服务器接口和加密密钥。
class _SyncSession {
  const _SyncSession(this.api, this.key);

  final SyncApi api;
  final Uint8List key;
}

/// 同步服务。规则：
/// - 每台主机有唯一 uuid，以 uuid 对应的“最后更新时间”决定方向：本地新则上传，服务器新则下载
/// - 主机的 syncedAt 记录最后一次与服务器一致时的时间，与 updatedAt 相等即为“已同步”
/// - 服务器上存在而本地没有的主机会被拉取到本地
/// - 从服务器删除后留下删除标记，各客户端将该主机改为“仅本地”，不再同步
/// - 载荷在客户端使用口令派生的密钥做 AES-GCM 加密，服务器只保存密文
/// - 未配置同步服务器时不影响任何本地功能
class SyncService extends ChangeNotifier {
  SyncService(
    this._settings,
    this._hosts,
    this._groups,
    this._keys, {
    SyncApi Function(String, String)? apiFactory,
  }) : _apiFactory = apiFactory ?? SyncApi.new;

  final SettingsRepository _settings;
  final HostRepository _hosts;
  final GroupRepository _groups;
  final KeyRepository _keys;
  final SyncApi Function(String, String) _apiFactory;

  SyncConfig config = const SyncConfig();
  bool syncing = false;
  String? lastError;
  SyncReport? lastReport;
  Timer? _timer;
  Uint8List? _key;
  String? _keyFor;
  Future<SyncReport>? _syncFuture;
  Future<void> _persistTail = Future.value();
  bool _stopped = false;

  /// 主机同步状态变化时回调（刷新主机列表）
  VoidCallback? onHostsChanged;

  static const _cfgKey = 'sync.config';

  /// 加载配置并启动自动同步
  Future<void> load() async {
    final j = await _settings.getJson(_cfgKey);
    config = SyncConfig(
      serverUrl: j['serverUrl'] as String? ?? '',
      token: await SecretStore.instance.open(j['token'] as String?) ?? '',
      passphrase:
          await SecretStore.instance.open(j['passphrase'] as String?) ?? '',
      intervalMinutes: (j['interval'] as num?)?.toInt() ?? 0,
      lastSyncAt: (j['lastSyncAt'] as num?)?.toInt(),
    );
    _stopped = false;
    _schedule();
    notifyListeners();
  }

  /// 保存配置
  Future<void> saveConfig(SyncConfig c) async {
    if (config.token != c.token || config.passphrase != c.passphrase) {
      _key = null;
      _keyFor = null;
    }
    config = c;
    await _persist();
    _schedule();
    notifyListeners();
  }

  /// 串行写入当前内存配置；并发保存时最后落盘的一定是最新配置，不会被旧快照覆盖。
  Future<void> _persist() {
    final done = _persistTail.then((_) async {
      final c = config;
      await _settings.setJson(_cfgKey, {
        'serverUrl': c.serverUrl.trim(),
        'token': await SecretStore.instance.seal(c.token),
        'passphrase': await SecretStore.instance.seal(c.passphrase),
        'interval': c.intervalMinutes,
        if (c.lastSyncAt != null) 'lastSyncAt': c.lastSyncAt,
      });
    });
    _persistTail = done.catchError((_) {});
    return done;
  }

  /// 按配置重建自动同步定时器；退出后不再恢复。
  void _schedule() {
    _timer?.cancel();
    _timer = null;
    if (!_stopped && config.isConfigured && config.intervalMinutes > 0) {
      _timer = Timer.periodic(Duration(minutes: config.intervalMinutes), (_) {
        syncNow().catchError((_) => SyncReport());
      });
    }
  }

  SyncApi get _api => _apiFactory(config.serverUrl, config.token);

  /// 派生加密密钥（盐由令牌决定，同一数据空间内各客户端一致）
  Future<Uint8List> _cryptoKey(SyncConfig c) async {
    final id = '${c.token}\u0000${c.passphrase}';
    if (_key != null && _keyFor == id) return _key!;
    final salt = await CryptoUtils.sha256(
      utf8.encode('remlark-sync:${c.token}'),
    );
    final key = await CryptoUtils.deriveKey(c.passphrase, salt);
    _key = key;
    _keyFor = id;
    return key;
  }

  /// 固定当前配置的服务器和密钥，同步途中修改配置不会混用新旧服务器或口令。
  Future<_SyncSession> _session() async {
    final c = config;
    return _SyncSession(_apiFactory(c.serverUrl, c.token), await _cryptoKey(c));
  }

  /// 测试连接
  Future<void> testConnection(SyncConfig c) =>
      _apiFactory(c.serverUrl, c.token).ping();

  /// 单台主机快照先压缩再加密，各主机保留独立 UUID 和配置修改版本。
  Future<String> _encode(_SyncSession s, HostEntry h) async {
    String? groupName;
    if (h.groupUuid != null) {
      for (final g in await _groups.list()) {
        if (g.uuid == h.groupUuid) groupName = g.name;
      }
    }
    final keyIds = HostSyncBundle.referencedKeyUuids(h);
    final keys = await Future.wait(keyIds.map(_keys.get));
    final payload = jsonEncode(
      HostSyncBundle(
        host: h,
        groupName: groupName,
        keys: keys.whereType<KeyEntry>().toList(),
      ).toJson(),
    );
    return CryptoUtils.encryptCompressedString(s.key, payload);
  }

  /// 解密并校验主机身份，然后以一个事务应用完整主机快照。
  Future<bool> _apply(
    _SyncSession s,
    String expectedUuid,
    String cipher,
    int remoteUpdatedAt,
  ) async {
    final plain = await CryptoUtils.decryptCompressedString(s.key, cipher);
    final bundle = HostSyncBundle.fromJson(
      jsonDecode(plain) as Map<String, dynamic>,
    );
    bundle.verifyServerRecord(expectedUuid, remoteUpdatedAt);
    return _hosts.transaction(() async {
      final local = await _hosts.getByUuid(expectedUuid);
      // 网络等待期间产生的较新本机编辑继续待同步，不被下载时的旧版本覆盖。
      if (local != null && local.updatedAt > remoteUpdatedAt) return false;
      for (final key in bundle.keys) {
        await _keys.save(key);
      }
      final groupUuid = bundle.groupName == null
          ? null
          : (await _groups.ensureByName(bundle.groupName!)).uuid;
      await _hosts.save(
        bundle.forDevice(
          local: local,
          groupUuid: groupUuid,
          updatedAt: remoteUpdatedAt,
        ),
        touch: false,
      );
      return true;
    });
  }

  /// 上传一台主机
  Future<bool> _push(
    _SyncSession s,
    HostEntry h, {
    bool restoreDeleted = false,
  }) async {
    final ok = await s.api.put(
      h.uuid,
      h.updatedAt,
      await _encode(s, h),
      restoreDeleted: restoreDeleted,
    );
    if (ok) {
      await _hosts.setSyncState(h.uuid, enabled: true, syncedAt: h.updatedAt);
    }
    return ok;
  }

  /// 立即同步
  Future<SyncReport> syncNow() {
    if (_syncFuture != null) return _syncFuture!;
    if (!config.isConfigured) {
      return Future.error(StateError('sync not configured'));
    }
    // 同一轮同步共享任务，手动和定时同时触发时都等待真实结果。
    return _syncFuture = Future<SyncReport>.microtask(_runSync)
        .whenComplete(() => _syncFuture = null);
  }

  /// 执行单轮同步；并发入口由 syncNow 合并。
  Future<SyncReport> _runSync() async {
    syncing = true;
    lastError = null;
    notifyListeners();
    final report = SyncReport();
    final sw = Stopwatch()..start();
    AppLog.i('sync', '开始同步');
    try {
      final s = await _session();
      final remote = await s.api.index();
      final locals = await _hosts.listSyncEnabled();
      final localIds = <String>{};
      final toPull = <String>{};
      for (final l in locals) {
        localIds.add(l.uuid);
        final r = remote[l.uuid];
        if (r == null) {
          if (await _push(s, l)) {
            report.pushed++;
          } else {
            toPull.add(l.uuid);
          }
        } else if (r.deleted) {
          await _hosts.setSyncState(l.uuid, enabled: false, syncedAt: null);
          report.detached++;
        } else if (r.updatedAt == l.updatedAt) {
          if (l.syncedAt != l.updatedAt) {
            // 两端可能同毫秒修改；待同步记录先读取服务端已提交的版本。
            toPull.add(l.uuid);
          } else {
            report.unchanged++;
          }
        } else if (l.updatedAt > r.updatedAt) {
          if (await _push(s, l)) {
            report.pushed++;
          } else {
            toPull.add(l.uuid);
          }
        } else {
          toPull.add(l.uuid);
        }
      }
      // 服务器有、本地未参与同步或不存在的主机
      for (final r in remote.values) {
        if (r.deleted || localIds.contains(r.uuid)) continue;
        final local = await _hosts.getByUuid(r.uuid);
        if (local != null && local.updatedAt > r.updatedAt) {
          if (await _push(s, local.copyWith(syncEnabled: true))) {
            report.pushed++;
          } else {
            toPull.add(r.uuid);
          }
        } else {
          toPull.add(r.uuid);
        }
      }
      if (toPull.isNotEmpty) {
        final payloads = await s.api.fetch(toPull.toList());
        for (final uuid in toPull) {
          final item = payloads[uuid];
          if (item == null) {
            throw StateError('Missing host sync payload: $uuid');
          }
          if (item.deleted) {
            final local = await _hosts.getByUuid(uuid);
            if (local?.syncEnabled ?? false) {
              await _hosts.setSyncState(uuid, enabled: false, syncedAt: null);
              report.detached++;
            }
          } else {
            if (item.payload == null) {
              throw FormatException('Missing host sync ciphertext: $uuid');
            }
            if (await _apply(s, uuid, item.payload!, item.updatedAt)) {
              report.pulled++;
            }
          }
        }
      }
      lastReport = report;
      AppLog.i(
        'sync',
        '同步完成 ${sw.elapsedMilliseconds}ms：推送 ${report.pushed}，拉取 ${report.pulled}，'
            '未变 ${report.unchanged}，解除 ${report.detached}',
      );
      // 只记录完成时间，不重建定时器：避免退出后被同步结束重新启动自动同步。
      config = config.copyWith(
        lastSyncAt: DateTime.now().millisecondsSinceEpoch,
      );
      await _persist();
    } catch (e, st) {
      lastError = e is SecretBoxAuthenticationError
          ? 'sync.error.passphrase'
          : '$e';
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
      if (fresh != null) {
        await _push(await _session(), fresh, restoreDeleted: true);
      }
    } catch (_) {}
    onHostsChanged?.call();
  }

  /// 从同步服务器删除该主机，之后不再同步（本地保留）
  Future<void> removeFromServer(String uuid) async {
    if (config.isConfigured) await _api.delete(uuid);
    await _hosts.setSyncState(uuid, enabled: false, syncedAt: null);
    onHostsChanged?.call();
  }

  /// 停止自动同步（退出时调用；界面仍可能在监听，因此不 dispose）
  void stop() {
    _stopped = true;
    _timer?.cancel();
    _timer = null;
  }

  @override
  void dispose() {
    stop();
    super.dispose();
  }
}
