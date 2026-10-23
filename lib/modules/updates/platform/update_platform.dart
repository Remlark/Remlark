import 'dart:ffi';
import 'dart:io';

import 'update_platform_linux.dart';
import '../install/install_plan.dart';
import 'update_platform_macos.dart';
import 'update_platform_windows.dart';

/// 各平台独立定义发布包与安装助手，助手等待主进程退出后完成升级。
abstract class UpdatePlatform {
  /// 以进程 ABI 选择兼容的附件；macOS 为通用包。
  factory UpdatePlatform.current() {
    if (Platform.isMacOS) return MacosUpdatePlatform(Abi.current());
    if (Platform.isWindows) return WindowsUpdatePlatform(Abi.current());
    return LinuxUpdatePlatform(
      Abi.current(),
      executable: Platform.resolvedExecutable,
    );
  }

  /// 根据已验证的版本生成安装包名，不支持的架构返回 null。
  String? assetName(String version);

  /// 下载验证后准备安装；失败时不能退出当前应用。
  Future<InstallPlan> prepare(InstallContext context);
}
