import '../../l10n/app_localizations.dart';

/// Agent 实现类型
enum AgentKind {
  /// DeepSeek Harness（dsh，应用内安装，以 ACP 子进程运行；值保持旧名以兼容已保存的配置）
  deepseekCli('deepseek_cli'),

  /// OpenAI 兼容 HTTP API（需填写接口地址与模型，如 Ollama、各家兼容接口）
  openaiApi('openai_api'),

  /// Codex（应用内安装，以 app-server 子进程运行，使用 ChatGPT 账号登录）
  codex('codex');

  const AgentKind(this.value);

  final String value;

  /// 类型显示名称（按界面语言）
  String get label => switch (this) {
    AgentKind.deepseekCli => 'DeepSeek Harness',
    AgentKind.codex => 'Codex',
    AgentKind.openaiApi => S.current.t('agent.kind.openai'),
  };

  /// Agent 是否自己保存对话上下文（dsh 会话、Codex 线程）：续聊时只发本轮内容，并保存外部会话 id
  bool get keepsContext => this == deepseekCli || this == codex;

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
    this.reasoningEffort = '',
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

  /// 推理强度（Codex 使用），空字符串为模型默认
  final String reasoningEffort;
  final bool isActive;
  final int createdAt;

  AgentSettings copyWith({bool? isActive, String? model, String? reasoningEffort}) => AgentSettings(
    uuid: uuid,
    name: name,
    kind: kind,
    command: command,
    args: args,
    endpoint: endpoint,
    apiKey: apiKey,
    model: model ?? this.model,
    systemPrompt: systemPrompt,
    reasoningEffort: reasoningEffort ?? this.reasoningEffort,
    isActive: isActive ?? this.isActive,
    createdAt: createdAt,
  );
}
