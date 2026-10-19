import 'dart:convert';
import 'dart:io';

import '../../utils/crypto_utils.dart';
import '../../utils/id_utils.dart';
import '../hosts/group_repository.dart';
import '../hosts/host_model.dart';
import '../hosts/host_repository.dart';
import '../keys/key_model.dart';
import '../keys/key_repository.dart';
import '../keys/key_utils.dart';
import '../snippets/snippet_model.dart';
import '../snippets/snippet_repository.dart';
import 'ssh_config_parser.dart';

/// 导入结果
class ImportResult {
  int hosts = 0;
  int keys = 0;
  int snippets = 0;
  int skipped = 0;
}

/// 导出文件需要口令
class ImportNeedsPassphrase implements Exception {}

/// 批量导入导出服务：JSON 格式（可选口令加密），以及导入 ~/.ssh/config
class ImportExportService {
  ImportExportService(this._hosts, this._groups, this._keys, this._snippets);

  final HostRepository _hosts;
  final GroupRepository _groups;
  final KeyRepository _keys;
  final SnippetRepository _snippets;

  static const _format = 'remlark-export';

  /// 导出全部主机、分组、密钥、快捷指令。
  /// [withSecrets] 为 true 时包含密码与私钥，此时建议设置 [passphrase] 加密
  Future<void> export(String path, {required bool withSecrets, String? passphrase}) async {
    final hosts = await _hosts.listByProtocols(HostProtocol.values.toSet());
    final groups = await _groups.list();
    final keys = withSecrets ? await _keys.list() : <KeyEntry>[];
    final snippets = await _snippets.list();
    final data = {
      'groups': [
        for (final g in groups) {'uuid': g.uuid, 'name': g.name, 'sortOrder': g.sortOrder},
      ],
      'hosts': [
        for (final h in hosts) {...h.toPortableJson(withSecrets: withSecrets), 'groupUuid': h.groupUuid},
      ],
      'keys': [for (final k in keys) k.toJson()],
      'snippets': [for (final s in snippets) s.toJson()],
    };
    Map<String, dynamic> out;
    if (passphrase != null && passphrase.isNotEmpty) {
      final salt = CryptoUtils.randomBytes(16);
      final key = await CryptoUtils.deriveKey(passphrase, salt);
      out = {
        'format': _format,
        'version': 1,
        'encrypted': true,
        'salt': base64Encode(salt),
        'data': await CryptoUtils.encryptString(key, jsonEncode(data)),
      };
    } else {
      out = {'format': _format, 'version': 1, 'encrypted': false, 'data': data};
    }
    await File(path).writeAsString(const JsonEncoder.withIndent('  ').convert(out));
  }

  /// 文件是否加密
  Future<bool> isEncrypted(String path) async {
    final j = jsonDecode(await File(path).readAsString()) as Map;
    return j['encrypted'] == true;
  }

  /// 导入 JSON 文件；同 uuid 已存在时，仅当导入数据更新时覆盖
  Future<ImportResult> import(String path, {String? passphrase}) async {
    final j = jsonDecode(await File(path).readAsString()) as Map<String, dynamic>;
    if (j['format'] != _format) throw const FormatException('unknown file format');
    Map<String, dynamic> data;
    if (j['encrypted'] == true) {
      if (passphrase == null || passphrase.isEmpty) throw ImportNeedsPassphrase();
      final key = await CryptoUtils.deriveKey(passphrase, base64Decode(j['salt'] as String));
      data = jsonDecode(await CryptoUtils.decryptString(key, j['data'] as String)) as Map<String, dynamic>;
    } else {
      data = j['data'] as Map<String, dynamic>;
    }
    final result = ImportResult();
    final existingGroups = {for (final g in await _groups.list()) g.uuid};
    for (final g in (data['groups'] as List? ?? []).cast<Map>()) {
      if (existingGroups.contains(g['uuid'])) continue;
      await _groups.save(
        GroupEntry(
          uuid: g['uuid'] as String,
          name: g['name'] as String,
          sortOrder: (g['sortOrder'] as num?)?.toInt() ?? 0,
        ),
      );
    }
    for (final k in (data['keys'] as List? ?? []).cast<Map<String, dynamic>>()) {
      await _keys.save(KeyEntry.fromJson(k));
      result.keys++;
    }
    for (final hj in (data['hosts'] as List? ?? []).cast<Map<String, dynamic>>()) {
      final h = HostEntry.fromPortableJson(hj).copyWith(groupUuid: () => hj['groupUuid'] as String?);
      final local = await _hosts.getByUuid(h.uuid);
      if (local != null && local.updatedAt >= h.updatedAt) {
        result.skipped++;
        continue;
      }
      await _hosts.save(
        h.copyWith(
          syncEnabled: local?.syncEnabled ?? false,
          syncedAt: () => local?.syncedAt,
          hostKeyFingerprint: () => local?.hostKeyFingerprint,
        ),
        touch: false,
      );
      result.hosts++;
    }
    final existingSnippets = {for (final s in await _snippets.list()) s.uuid};
    for (final s in (data['snippets'] as List? ?? []).cast<Map<String, dynamic>>()) {
      final entry = SnippetEntry.fromJson(s);
      if (existingSnippets.contains(entry.uuid)) continue;
      await _snippets.save(entry);
      result.snippets++;
    }
    return result;
  }

  /// 从 OpenSSH 配置文件导入（跳过通配符 Host），IdentityFile 会导入为密钥
  Future<ImportResult> importSshConfig(String path, {String? groupUuid}) async {
    final entries = SshConfigParser.parse(await File(path).readAsString());
    final result = ImportResult();
    final now = DateTime.now().millisecondsSinceEpoch;
    final byAlias = <String, String>{};
    final keyByPath = <String, String>{};
    // 先创建所有主机（不含跳板），再回填 ProxyJump
    final created = <(SshConfigEntry, HostEntry)>[];
    for (final e in entries) {
      String? keyUuid;
      if (e.identityFile != null) {
        keyUuid = keyByPath[e.identityFile!] ??= await _importKeyFile(e.identityFile!, result) ?? '';
        if (keyUuid.isEmpty) keyUuid = null;
      }
      final h = HostEntry(
        uuid: IdUtils.newId(),
        protocol: HostProtocol.ssh,
        name: e.alias,
        groupUuid: groupUuid,
        address: e.hostName ?? e.alias,
        port: e.port ?? 22,
        username: e.user ?? '',
        authType: keyUuid != null ? AuthType.key : AuthType.password,
        keyUuid: keyUuid,
        updatedAt: now,
        createdAt: now,
      );
      byAlias[e.alias] = h.uuid;
      created.add((e, h));
    }
    for (final (e, h) in created) {
      final chain = <String>[];
      for (final j in e.proxyJump) {
        final id = byAlias[j];
        if (id != null) chain.add(id);
      }
      await _hosts.save(h.copyWith(jumpChain: chain));
      result.hosts++;
    }
    return result;
  }

  /// 导入私钥文件，返回密钥 uuid；加密私钥（需要口令）跳过
  Future<String?> _importKeyFile(String path, ImportResult result) async {
    try {
      final f = File(path);
      if (!f.existsSync()) return null;
      final pem = await f.readAsString();
      if (KeyUtils.isEncrypted(pem)) {
        result.skipped++;
        return null;
      }
      final pub = KeyUtils.derivePublic(pem, null, f.uri.pathSegments.last);
      final k = KeyEntry(
        uuid: IdUtils.newId(),
        name: f.uri.pathSegments.last,
        keyType: pub.keyType,
        privateKey: pem,
        publicKey: pub.publicLine,
        createdAt: DateTime.now().millisecondsSinceEpoch,
      );
      await _keys.save(k);
      result.keys++;
      return k.uuid;
    } catch (_) {
      result.skipped++;
      return null;
    }
  }
}
