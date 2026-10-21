/// 由 tools/utils/app_version.py 从 VERSION 注入；直接使用 Flutter 工具时标记为开发版本。
const appVersion = String.fromEnvironment(
  'REMLARK_VERSION',
  defaultValue: 'development',
);
