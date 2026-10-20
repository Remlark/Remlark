import 'dart:async';

import '../../../l10n/app_localizations.dart';
import '../runtime/json_rpc_connection.dart';
import 'codex_app_server.dart';
import 'codex_environment.dart';
import 'codex_types.dart';

/// 一次进行中的浏览器登录
class CodexLoginSession {
  CodexLoginSession({required this.authUrl, required this.completed, required this._cancel});

  /// 需要在浏览器中打开的登录地址
  final String authUrl;

  /// 登录完成时返回新账号；取消时返回 null；失败时抛出 [CodexException]
  final Future<CodexAccount?> completed;

  final Future<void> Function() _cancel;

  /// 取消登录（原有账号保持不变）
  Future<void> cancel() => _cancel();
}

/// Codex 账号与模型：每次操作启动一个短生命周期的 app-server，用完即关闭；
/// 登录在临时 CODEX_HOME 中进行（与 GitAstra 相同），期间进程一直运行（它负责接收浏览器的登录回调），
/// 完成后把凭据替换到 Agent 自己的目录。登录或退出后重启该 Agent 的常驻进程
class CodexAccountService {
  CodexAccountService({CodexAppServer? server, Future<CodexEnvironment> Function()? environment})
    : _custom = server,
      _environment = environment ?? CodexEnvironment.current;

  final Future<CodexEnvironment> Function() _environment;

  final CodexAppServer? _custom;

  /// 未指定时使用全局实例（使用时再取，测试可替换全局实例）
  CodexAppServer get _server => _custom ?? CodexAppServer.shared;

  /// 登录等待的最长时间
  static const loginTimeout = Duration(minutes: 15);

  static String _t(String key, [Map<String, Object?> args = const {}]) => S.current.t(key, args);

  /// 在一个临时进程中执行 [action]，结束后关闭
  Future<T> _withConnection<T>(String homeId, Future<T> Function(JsonRpcConnection c) action) async {
    final conn = await _server.open(homeId);
    try {
      return await action(conn);
    } on JsonRpcException catch (e) {
      throw CodexException(e.message);
    } finally {
      await conn.close();
    }
  }

  /// 读取 Agent [homeId] 当前登录的账号，未登录返回 null
  Future<CodexAccount?> readAccount(String homeId) => _withConnection(homeId, readAccountWith);

  /// 在已有连接中读取账号
  static Future<CodexAccount?> readAccountWith(JsonRpcConnection c) async {
    final r = await c.call('account/read', {'refreshToken': false}, timeout: const Duration(seconds: 30));
    return CodexAccount.fromJson(r['account']);
  }

  /// 获取可选模型（不含隐藏模型），保持 Codex 返回的顺序
  Future<List<CodexModel>> listModels(String homeId) => _withConnection(homeId, (c) async {
    final models = <CodexModel>[];
    String? cursor;
    for (var page = 0; page < 10; page++) {
      final r = await c.call('model/list', {
        'includeHidden': false,
        'cursor': ?cursor,
      }, timeout: const Duration(seconds: 30));
      for (final item in (r['data'] as List?) ?? const []) {
        final m = CodexModel.fromJson(item);
        if (m != null) models.add(m);
      }
      cursor = r['nextCursor']?.toString();
      if (cursor == null || cursor.isEmpty) break;
    }
    return models;
  });

  /// 退出登录
  Future<void> logout(String homeId) async {
    await _withConnection(homeId, (c) => c.call('account/logout', const {}, timeout: const Duration(seconds: 30)));
    await _server.restart(homeId);
  }

  /// 开始 ChatGPT 账号的浏览器登录。已登录时也可调用：完成后新账号替换原账号，取消则原账号不变。
  /// 登录在临时目录中进行，不占用 Agent 自己的目录；成功后采用凭据，取消或失败时删除临时目录
  Future<CodexLoginSession> startLogin(String homeId) async {
    final staging = CodexEnvironment.newStagingHomeId();
    final JsonRpcConnection conn;
    try {
      conn = await _server.open(staging);
    } catch (_) {
      await (await _environment()).removeHome(staging);
      rethrow;
    }
    final result = Completer<bool>();
    final sub = conn.notifications.listen((n) {
      if (n.method != 'account/login/completed' || result.isCompleted) return;
      if (n.params['success'] == true) {
        result.complete(true);
      } else {
        result.completeError(CodexException(_t('codex.err.login', {'error': '${n.params['error'] ?? ''}'})));
      }
    });
    // 进程意外退出时结束等待
    unawaited(
      conn.done.then((_) {
        if (!result.isCompleted) {
          result.completeError(CodexException(_t('codex.err.login', {'error': conn.closeReason ?? ''})));
        }
      }),
    );
    final Map<String, dynamic> start;
    try {
      start = await conn.call('account/login/start', {'type': 'chatgpt'}, timeout: const Duration(seconds: 30));
    } catch (e) {
      await sub.cancel();
      await conn.close();
      await (await _environment()).removeHome(staging);
      throw CodexException(_t('codex.err.login', {'error': '$e'}));
    }
    final loginId = '${start['loginId'] ?? ''}';
    var cancelled = false;

    /// 等待登录完成并读取新账号；关闭登录进程后把凭据替换到 Agent 的目录，并重启它的常驻进程
    Future<CodexAccount?> wait() async {
      var adopted = false;
      try {
        final ok = await result.future.timeout(
          loginTimeout,
          onTimeout: () => throw CodexException(_t('codex.err.login_timeout')),
        );
        if (!ok || cancelled) return null;
        final account = await readAccountWith(conn);
        await sub.cancel();
        await conn.close();
        await (await _environment()).adoptLogin(staging, homeId);
        adopted = true;
        await _server.restart(homeId);
        return account;
      } catch (_) {
        if (cancelled) return null;
        rethrow;
      } finally {
        await sub.cancel();
        await conn.close();
        // 取消、失败时删除临时目录；采用成功时已由 adoptLogin 删除
        if (!adopted) await (await _environment()).removeHome(staging);
      }
    }

    return CodexLoginSession(
      authUrl: '${start['authUrl'] ?? ''}',
      completed: wait(),
      cancel: () async {
        if (cancelled || result.isCompleted) return;
        cancelled = true;
        try {
          await conn.call('account/login/cancel', {'loginId': loginId}, timeout: const Duration(seconds: 5));
        } catch (_) {
          // 进程已退出：直接结束等待
        }
        if (!result.isCompleted) result.complete(false);
      },
    );
  }
}
