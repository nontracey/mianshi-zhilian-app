import 'package:flutter/material.dart';

part 'l10n_zh.dart';
part 'l10n_en.dart';

class L10n {
  static const defaultLanguage = 'zh';
  static String currentLanguage = defaultLanguage;

  static const Map<String, Map<String, String>> _localizedValues = {
    'zh': _zh,
    'en': _en,
  };

  static String resolveLanguage(String language) {
    return _localizedValues.containsKey(language) ? language : defaultLanguage;
  }

  static String get(String key, String language) {
    final normalizedLanguage = resolveLanguage(language);
    final map = _localizedValues[normalizedLanguage] ?? _zh;
    return map[key] ?? _zh[key] ?? _en[key] ?? key;
  }

  static String getp(String key, String language, Map<String, String> params) {
    final template = get(key, language);
    return params.entries.fold(template, (result, entry) {
      return result.replaceAll('{${entry.key}}', entry.value);
    });
  }

  static List<String> get supportedLanguageCodes =>
      _localizedValues.keys.toList(growable: false);

  static List<Locale> get supportedLocales =>
      supportedLanguageCodes.map(Locale.new).toList(growable: false);
}
