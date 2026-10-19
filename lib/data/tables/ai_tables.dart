import 'package:drift/drift.dart';

/// AI Agent 配置表
@TableIndex(name: 'idx_agents_uuid', columns: {#uuid}, unique: true)
@TableIndex(name: 'idx_agents_active', columns: {#isActive})
@TableIndex(name: 'idx_agents_created', columns: {#createdAt})
class AgentConfigs extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get uuid => text()();
  TextColumn get name => text()();

  /// 实现类型：deepseek_cli / openai_api
  TextColumn get kind => text()();
  TextColumn get command => text().withDefault(const Constant(''))();
  TextColumn get args => text().withDefault(const Constant(''))();
  TextColumn get endpoint => text().withDefault(const Constant(''))();
  TextColumn get apiKeyEnc => text().nullable()();
  TextColumn get model => text().withDefault(const Constant(''))();
  TextColumn get systemPrompt => text().withDefault(const Constant(''))();
  BoolColumn get isActive => boolean().withDefault(const Constant(false))();
  IntColumn get createdAt => integer()();
}

/// 聊天会话表
@TableIndex(name: 'idx_chat_sessions_uuid', columns: {#uuid}, unique: true)
@TableIndex(name: 'idx_chat_sessions_updated', columns: {#updatedAt})
@TableIndex(name: 'idx_chat_sessions_agent', columns: {#agentUuid})
class ChatSessions extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get uuid => text()();
  TextColumn get title => text()();
  TextColumn get agentUuid => text()();
  TextColumn get agentName => text()();
  TextColumn get model => text().withDefault(const Constant(''))();
  TextColumn get hostName => text().withDefault(const Constant(''))();

  /// CLI 类 Agent 的会话 id（用于续接上下文）
  TextColumn get externalSessionId => text().nullable()();
  IntColumn get createdAt => integer()();
  IntColumn get updatedAt => integer()();
}

/// 聊天消息表
@TableIndex(name: 'idx_chat_messages_session', columns: {#sessionId, #createdAt})
class ChatMessages extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get sessionId => integer()();

  /// 角色：user / assistant / error
  TextColumn get role => text()();
  TextColumn get content => text()();
  IntColumn get inputTokens => integer().withDefault(const Constant(0))();
  IntColumn get outputTokens => integer().withDefault(const Constant(0))();
  IntColumn get createdAt => integer()();
}

/// Token 用量明细：每次请求一条，按天聚合统计
@TableIndex(name: 'idx_token_day', columns: {#day})
@TableIndex(name: 'idx_token_day_agent', columns: {#day, #agentUuid})
@TableIndex(name: 'idx_token_day_model', columns: {#day, #model})
class TokenUsages extends Table {
  IntColumn get id => integer().autoIncrement()();

  /// 日期键 yyyy-MM-dd（本地时间）
  TextColumn get day => text()();
  TextColumn get agentUuid => text()();
  TextColumn get agentName => text()();
  TextColumn get model => text()();
  IntColumn get inputTokens => integer()();
  IntColumn get outputTokens => integer()();
  IntColumn get createdAt => integer()();
}
