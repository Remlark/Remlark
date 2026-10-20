import 'package:flutter/foundation.dart';

import '../agent_config.dart';

/// Agent 运行环境：某类 Agent 需要在本机安装的程序（如 dsh），由应用下载、更新与移除。
/// 新增需要本地运行环境的 Agent 时实现此接口，并在 [AgentRuntimes] 中注册；
/// 界面（添加 / 编辑 Agent、Agent 列表）只依赖此接口。
abstract class AgentRuntime implements Listenable {
  /// 显示名称，例如 “DeepSeek Harness”
  String get displayName;

  /// 未安装时的说明文本 key（说明下载什么、占用多少空间）
  String get notInstalledKey;

  /// 是否已读取过本地安装状态
  bool get loaded;

  /// 是否已安装
  bool get installed;

  /// 已安装版本，未安装为 null
  String? get installedVersion;

  /// 最新版本，尚未查询或查询失败为 null
  String? get latestVersion;

  /// 是否有可升级的新版本
  bool get updateAvailable;

  /// 是否正在安装或升级
  bool get busy;

  /// 安装中的阶段文本 key 与参数（未在安装时为 null）
  String? get stageKey;
  Map<String, Object?> get stageArgs;

  /// 安装进度（0~1），未知时为 null
  double? get progress;

  /// 最近一次安装或查询失败的原因（已翻译）
  String? get error;

  /// 只读取本机的安装状态与版本，不联网（Agent 列表使用）。不抛出异常
  Future<void> loadLocal();

  /// 读取本机版本并检测更新：缓存过期或 [force] 时联网查询最新版本（Agent 编辑框使用）。不抛出异常
  Future<void> checkUpdate({bool force = false});

  /// 安装或升级到最新版本，成功返回 true，失败原因见 [error]
  Future<bool> install();

  /// 移除运行环境
  Future<void> uninstall();
}

/// 各类 Agent 的运行环境注册表；不需要本地运行环境的 Agent（如 OpenAI 兼容 API）返回 null
class AgentRuntimes {
  AgentRuntimes(this._byKind);

  final Map<AgentKind, AgentRuntime> _byKind;

  /// [kind] 需要的运行环境
  AgentRuntime? of(AgentKind kind) => _byKind[kind];

  /// 所有运行环境
  Iterable<AgentRuntime> get all => _byKind.values;
}
