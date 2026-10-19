/// 快捷指令类型
enum SnippetKind {
  /// 普通字符串输入
  text('text'),

  /// 系统免密登录（把本机系统 SSH 公钥安装到服务器，仅 macOS / Linux）
  installSystemKey('install_system_key');

  const SnippetKind(this.value);

  final String value;

  static SnippetKind parse(String? v) => SnippetKind.values.firstWhere((e) => e.value == v, orElse: () => text);
}

/// 快捷指令领域模型
class SnippetEntry {
  const SnippetEntry({
    required this.uuid,
    required this.name,
    this.content = '',
    this.kind = SnippetKind.text,
    this.autoEnter = true,
    this.sortOrder = 0,
  });

  final String uuid;
  final String name;
  final String content;
  final SnippetKind kind;
  final bool autoEnter;
  final int sortOrder;

  /// 是否为特殊动作（非普通字符串）
  bool get isAction => kind != SnippetKind.text;

  Map<String, dynamic> toJson() => {
    'uuid': uuid,
    'name': name,
    'content': content,
    'kind': kind.value,
    'autoEnter': autoEnter,
    'sortOrder': sortOrder,
  };

  factory SnippetEntry.fromJson(Map<String, dynamic> j) => SnippetEntry(
    uuid: j['uuid'] as String,
    name: j['name'] as String? ?? '',
    content: j['content'] as String? ?? '',
    kind: SnippetKind.parse(j['kind'] as String?),
    autoEnter: j['autoEnter'] != false,
    sortOrder: (j['sortOrder'] as num?)?.toInt() ?? 0,
  );
}
