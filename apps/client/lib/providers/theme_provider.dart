import 'package:flutter/material.dart';
import '../models/app_settings.dart';

class ThemeProvider extends ChangeNotifier {
  AppThemeType _themeType = AppThemeType.system;
  Color _primaryColor = const Color(0xFF1A2B4A);
  Color _accentColor = const Color(0xFF3078F0);
  double _fontScale = 1.0;
  String _cardDensity = 'comfortable';
  String _language = 'zh';

  AppThemeType get themeType => _themeType;
  Color get primaryColor => _primaryColor;
  Color get accentColor => _accentColor;
  double get fontScale => _fontScale;
  String get cardDensity => _cardDensity;
  String get language => _language;

  void updateFromSettings(AppSettings settings) {
    final changed = _themeType != settings.themeType ||
        _primaryColor != settings.primaryColor ||
        _accentColor != settings.accentColor ||
        _fontScale != settings.fontScale ||
        _cardDensity != settings.cardDensity;
    _themeType = settings.themeType;
    _primaryColor = settings.primaryColor;
    _accentColor = settings.accentColor;
    _fontScale = settings.fontScale;
    _cardDensity = settings.cardDensity;
    _language = settings.language;
    if (changed) notifyListeners();
  }

  void updateLanguage(String lang) {
    if (_language == lang) return;
    _language = lang;
    notifyListeners();
  }
}