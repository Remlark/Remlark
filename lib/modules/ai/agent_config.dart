/// Agent 实现类型
enum AgentKind {
  /// DeepSeek Harness（dsh，应用内安装，以 ACP 子进程运行；值保持旧名以兼容已保存的配置）
  deepseekCli('deepseek_cli'),

  /// OpenAI 兼容 HTTP API（DeepSeek API 等）
  openaiApi('openai_api');

  const AgentKind(this.value);

  final String value;

  static AgentKind parse(String? v) => AgentKind.values.firstWhere((e) => e.value == v, orElse: () => deepseekCli);
}

/// Agent 配置（明文，仅内存）
class AgentSettings {
  const AgentSettings({
    required this.uuid,
    required this.name,
    required this.kind,
    this.command = '',
    this.args = '',
    this.endpoint = '',
    this.apiKey,
    this.model = '',
    this.systemPrompt = '',
    this.isActive = false,
    required this.createdAt,
  });

  final String uuid;
  final String name;
  final AgentKind kind;

  /// 旧版 CLI 可执行文件路径（已不使用，保留以兼容数据库与同步）
  final String command;

  /// 旧版 CLI 额外参数（已不使用，保留以兼容数据库与同步）
  final String args;

  /// API 地址
  final String endpoint;
  final String? apiKey;
  final String model;
  final String systemPrompt;
  final bool isActive;
  final int createdAt;

  AgentSettings copyWith({bool? isActive}) => AgentSettings(
    uuid: uuid,
    name: name,
    kind: kind,
    command: command,
    args: args,
    endpoint: endpoint,
    apiKey: apiKey,
    model: model,
    systemPrompt: systemPrompt,
    isActive: isActive ?? this.isActive,
    createdAt: createdAt,
  );
}
