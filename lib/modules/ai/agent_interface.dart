// AI Agent 与 UI 交互的接口定义。
// 各种 Agent（DeepSeek Harness CLI、OpenAI 兼容 API 等）实现 [AiAgent]，
// UI 只依赖事件流 [AgentEvent]，从而可以对接任意 Agent。

/// 对话消息
class AgentMessage {
  const AgentMessage(this.role, this.content);

  /// 角色：user / assistant / system
  final String role;
  final String content;
}

/// Agent 事件
sealed class AgentEvent {
  const AgentEvent();
}

/// 增量文本
class AgentTextDelta extends AgentEvent {
  const AgentTextDelta(this.text);

  final String text;
}

/// 推理过程（可选显示）
class AgentReasoningDelta extends AgentEvent {
  const AgentReasoningDelta(this.text);

  final String text;
}

/// Token 用量；[estimated] 表示 Agent 未上报、由客户端估算
class AgentUsage extends AgentEvent {
  const AgentUsage({required this.inputTokens, required this.outputTokens, this.contextTokens, this.estimated = false});

  final int inputTokens;
  final int outputTokens;

  /// 上下文占用（未提供时为输入 + 输出）
  final int? contextTokens;
  final bool estimated;
}

/// Agent 侧会话 id（CLI 类 Agent 用于续接上下文）
class AgentSessionId extends AgentEvent {
  const AgentSessionId(this.id);

  final String id;
}

/// 错误
class AgentError extends AgentEvent {
  const AgentError(this.message);

  final String message;
}

/// Agent 请求
class AgentRequest {
  const AgentRequest({required this.history, required this.prompt, this.externalSessionId, this.systemPrompt = ''});

  /// 之前的对话（不含本次 prompt）
  final List<AgentMessage> history;
  final String prompt;
  final String? externalSessionId;
  final String systemPrompt;
}

/// AI Agent 接口
abstract class AiAgent {
  /// 显示名称
  String get name;

  /// 使用的模型名（用于统计）
  String get model;

  /// 发送请求，返回事件流；流结束表示本轮回答完成
  Stream<AgentEvent> send(AgentRequest request);

  /// 取消正在进行的请求
  void cancel();
}

/// 粗略估算 token 数（Agent 未上报用量时使用）：CJK 字符约 1 token，其他约 4 字符 1 token
int estimateTokens(String text) {
  var cjk = 0;
  var other = 0;
  for (final r in text.runes) {
    if (r >= 0x2E80) {
      cjk++;
    } else {
      other++;
    }
  }
  return cjk + (other / 4).ceil();
}
