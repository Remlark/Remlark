import 'package:drift/drift.dart';

import '../../data/database.dart';
import '../../utils/id_utils.dart';

/// 聊天记录仓库：会话与消息
class ChatRepository {
  ChatRepository(this._db);

  final AppDatabase _db;

  /// 最近的会话（updatedAt 索引倒序分页）
  Future<List<ChatSession>> listSessions({int limit = 200, int offset = 0}) {
    return (_db.select(_db.chatSessions)
          ..where((t) => t.updatedAt.isBiggerOrEqualValue(0))
          ..orderBy([(t) => OrderingTerm.desc(t.updatedAt)])
          ..limit(limit, offset: offset))
        .get();
  }

  /// 按 id 获取会话
  Future<ChatSession?> getSession(int id) =>
      (_db.select(_db.chatSessions)..where((t) => t.id.equals(id))).getSingleOrNull();

  /// 新建会话
  Future<ChatSession> createSession({
    required String title,
    required String agentUuid,
    required String agentName,
    required String model,
    String hostName = '',
  }) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    final id = await _db
        .into(_db.chatSessions)
        .insert(
          ChatSessionsCompanion.insert(
            uuid: IdUtils.newId(),
            title: title,
            agentUuid: agentUuid,
            agentName: agentName,
            model: Value(model),
            hostName: Value(hostName),
            createdAt: now,
            updatedAt: now,
          ),
        );
    return (await getSession(id))!;
  }

  /// 更新会话的外部 session id 与更新时间
  Future<void> touchSession(int id, {String? externalSessionId}) async {
    await (_db.update(_db.chatSessions)..where((t) => t.id.equals(id))).write(
      ChatSessionsCompanion(
        updatedAt: Value(DateTime.now().millisecondsSinceEpoch),
        externalSessionId: externalSessionId == null ? const Value.absent() : Value(externalSessionId),
      ),
    );
  }

  /// 会话的全部消息（sessionId + createdAt 复合索引）
  Future<List<ChatMessage>> messages(int sessionId) {
    return (_db.select(_db.chatMessages)
          ..where((t) => t.sessionId.equals(sessionId))
          ..orderBy([(t) => OrderingTerm.asc(t.createdAt), (t) => OrderingTerm.asc(t.id)]))
        .get();
  }

  /// 添加消息
  Future<void> addMessage(
    int sessionId,
    String role,
    String content, {
    int inputTokens = 0,
    int outputTokens = 0,
  }) async {
    await _db
        .into(_db.chatMessages)
        .insert(
          ChatMessagesCompanion.insert(
            sessionId: sessionId,
            role: role,
            content: content,
            inputTokens: Value(inputTokens),
            outputTokens: Value(outputTokens),
            createdAt: DateTime.now().millisecondsSinceEpoch,
          ),
        );
  }

  /// 删除会话及其消息
  Future<void> deleteSession(int id) async {
    await _db.transaction(() async {
      await (_db.delete(_db.chatMessages)..where((t) => t.sessionId.equals(id))).go();
      await (_db.delete(_db.chatSessions)..where((t) => t.id.equals(id))).go();
    });
  }
}
