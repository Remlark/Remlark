import '../runtime/agent_options.dart';

/// dsh 会话公布的配置项（ACP `configOptions`）：模型（category = model）与推理强度（category = thought_level）。
/// 选项可能分组（组内再有 options），值与显示名称不同（模型值为 JSON 字符串，名称为模型名）
class DshConfigOptions {
  DshConfigOptions._();

  /// 模型配置项
  static Map? model(Object? configOptions) => _find(configOptions, 'model', 'model');

  /// 推理强度配置项
  static Map? effort(Object? configOptions) => _find(configOptions, 'reasoning_effort', 'thought_level');

  static Map? _find(Object? configOptions, String id, String category) {
    if (configOptions is! List) return null;
    for (final o in configOptions.whereType<Map>()) {
      if (o['id'] == id || o['category'] == category) return o;
    }
    return null;
  }

  /// 展开（可能分组的）选项，返回叶子选项
  static List<Map> leaves(Object? options) => [
    if (options is List)
      for (final o in options.whereType<Map>()) ...(o['options'] is List ? leaves(o['options']) : [o]),
  ];

  /// 在配置项 [option] 中查找名称或值等于 [want] 的选项值，找不到返回 null
  static String? valueOf(Map option, String want) {
    for (final o in leaves(option['options'])) {
      if (o['name'] == want || o['value'] == want) return '${o['value']}';
    }
    return null;
  }

  /// 转换为界面使用的可选项：模型按名称保存；推理强度对所有模型相同，默认值为会话初始的当前值
  static AgentOptions toAgentOptions(Object? configOptions) {
    final m = model(configOptions);
    final e = effort(configOptions);
    final efforts = e == null ? const <String>[] : [for (final o in leaves(e['options'])) '${o['value']}'];
    final defaultEffort = e?['currentValue']?.toString();
    return AgentOptions([
      if (m != null)
        for (final o in leaves(m['options']))
          AgentModelOption(
            id: '${o['name'] ?? o['value']}',
            label: '${o['name'] ?? o['value']}',
            isDefault: o['value'] == m['currentValue'],
            efforts: efforts,
            defaultEffort: defaultEffort,
          ),
    ]);
  }
}
