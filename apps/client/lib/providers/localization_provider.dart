import 'package:flutter/material.dart';
import '../l10n/l10n.dart';

class LocalizationProvider extends ChangeNotifier {
  String _language;

  LocalizationProvider({String initialLanguage = 'zh'}) : _language = initialLanguage;

  String get language => _language;

  void setLanguage(String lang) {
    _language = lang;
    notifyListeners();
  }

  String get(String key) {
    return L10n.get(key, _language);
  }

  String getp(String key, Map<String, dynamic> params) {
    return L10n.getp(key, _language, params.map((k, v) => MapEntry(k, v.toString())));
  }
}
