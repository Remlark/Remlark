/// Agent 可选的模型与推理强度（由各运行环境从 Agent 读取，界面只依赖这些类型）
library;

/// 一个可选模型
class AgentModelOption {
  const AgentModelOption({
    required this.id,
    required this.label,
    this.isDefault = false,
    this.efforts = const [],
    this.defaultEffort,
  });

  /// 保存到 Agent 配置中的模型值
  final String id;

  /// 显示名称
  final String label;

  /// 是否为 Agent 的默认模型
  final bool isDefault;

  /// 该模型支持的推理强度（从低到高），为空表示不能选择
  final List<String> efforts;

  /// 默认推理强度，未知时为 null
  final String? defaultEffort;
}

/// Agent 的全部可选项
class AgentOptions {
  const AgentOptions(this.models, {this.hasDefault = true});

  final List<AgentModelOption> models;

  /// 是否有“默认模型”选项（OpenAI 兼容接口没有：未选择时使用固定的默认模型名）
  final bool hasDefault;

  /// 默认模型
  AgentModelOption? get defaultModel =>
      hasDefault ? models.where((m) => m.isDefault).firstOrNull ?? models.firstOrNull : null;

  /// 配置值 [model] 对应的模型（空字符串为默认模型），找不到返回 null
  AgentModelOption? modelFor(String model) =>
      model.isEmpty ? defaultModel : models.where((m) => m.id == model).firstOrNull;
}
