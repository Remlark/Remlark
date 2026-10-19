// Native assets 构建钩子：把预先编译好的 RDP 胶水库（native/rdp/scripts/build.sh 生成）
// 声明为代码资源，Flutter 会自动把它打包到各平台应用中（macOS Frameworks / Linux lib / Windows exe 目录）。
// 若对应平台架构的库尚未编译，则不声明资源，应用中的 RDP 功能会提示“原生库缺失”。
import 'dart:io';

import 'package:code_assets/code_assets.dart';
import 'package:hooks/hooks.dart';

void main(List<String> args) async {
  await build(args, (input, output) async {
    if (!input.config.buildCodeAssets) return;
    final code = input.config.code;
    final os = code.targetOS;
    final osDir = switch (os) {
      OS.macOS => 'macos',
      OS.linux => 'linux',
      OS.windows => 'windows',
      _ => null,
    };
    if (osDir == null) return;
    final arch = switch (code.targetArchitecture) {
      Architecture.x64 => 'x86_64',
      Architecture.arm64 => os == OS.linux ? 'aarch64' : 'arm64',
      _ => null,
    };
    if (arch == null) return;
    final file = input.packageRoot.resolve('build/native/$osDir-$arch/${os.dylibFileName('remlark_rdp')}');
    output.dependencies.add(file);
    if (!File.fromUri(file).existsSync()) return;
    output.assets.code.add(
      CodeAsset(package: input.packageName, name: 'rdp', linkMode: DynamicLoadingBundled(), file: file),
    );
  });
}
