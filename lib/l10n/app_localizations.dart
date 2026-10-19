import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'strings_en.dart';
import 'strings_zh.dart';

/// 多语言：通过 key 查找翻译文本，支持 {name} 形式的参数替换。
/// 新增或修改 UI 文本时需同时在 strings_zh.dart 与 strings_en.dart 中添加。
class S {
  S(this.locale);

  final Locale locale;

  /// 支持的语言
  static const supportedLocales = [Locale('zh'), Locale('en')];

  static const LocalizationsDelegate<S> delegate = _SDelegate();

  /// 获取当前上下文的翻译实例
  static S of(BuildContext context) {
    return Localizations.of<S>(context, S) ?? S(const Locale('zh'));
  }

  Map<String, String> get _table => locale.languageCode == 'zh' ? stringsZh : stringsEn;

  /// 翻译 [key]，[args] 中的值会替换文本中的 {name}
  String t(String key, [Map<String, Object?> args = const {}]) {
    var s = _table[key] ?? stringsEn[key] ?? key;
    args.forEach((k, v) => s = s.replaceAll('{$k}', '${v ?? ''}'));
    return s;
  }
}

class _SDelegate extends LocalizationsDelegate<S> {
  const _SDelegate();

  @override
  bool isSupported(Locale locale) => ['zh', 'en'].contains(locale.languageCode);

  @override
  // 同步加载，避免首帧空白
  Future<S> load(Locale locale) => SynchronousFuture(S(locale));

  @override
  bool shouldReload(covariant LocalizationsDelegate<S> old) => false;
}

/// BuildContext 便捷扩展：context.tr('key')
extension TrContext on BuildContext {
  String tr(String key, [Map<String, Object?> args = const {}]) => S.of(this).t(key, args);
}
