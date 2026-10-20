/// dsh 运行环境的公共类型
library;

/// dsh 相关错误（消息已按当前界面语言翻译，可直接显示）
class DshException implements Exception {
  DshException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// 安装阶段（界面显示进度文本）
enum DshInstallStage {
  /// 查询最新版本
  checking,

  /// 下载 Node.js 运行时（有进度）
  downloadingNode,

  /// npm 安装 dsh 及依赖（无法得知进度）
  installingDsh,

  /// 校验安装结果
  verifying,
}
