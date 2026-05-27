import 'package:flutter/material.dart';
import '../l10n/l10n.dart';

class LocalizationProvider extends ChangeNotifier {
  String _language = 'zh';

  String get language => _language;

  void setLanguage(String lang) {
    _language = lang;
    notifyListeners();
  }

  String get(String key) {
    return L10n.get(key, _language);
  }
}
