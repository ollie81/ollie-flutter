import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

// Same 10-language set as the web app (ourollie.space), and the same
// reasoning: the first 8 came from that app's own Vercel Analytics
// country breakdown, not a generic "top world languages" guess.
// Spanish and Chinese were added on top of that by direct request.
class SupportedLanguage {
  final String code;
  final String label;
  const SupportedLanguage(this.code, this.label);
}

const List<SupportedLanguage> kSupportedLanguages = [
  SupportedLanguage('en', 'English'),
  SupportedLanguage('pt', 'Português'),
  SupportedLanguage('rw', 'Ikinyarwanda'),
  SupportedLanguage('hi', 'हिन्दी'),
  SupportedLanguage('ur', 'اردو'),
  SupportedLanguage('ar', 'العربية'),
  SupportedLanguage('fr', 'Français'),
  SupportedLanguage('sw', 'Kiswahili'),
  SupportedLanguage('es', 'Español'),
  SupportedLanguage('zh', '中文'),
];

const String _prefsKey = 'ollie_language';

// A null value means "follow the system locale" (Flutter's own
// resolution against supportedLocales already falls back to English
// when the system locale isn't one of the 10 supported ones), same
// default behavior as the web app's fallbackLng.
class LocaleController {
  static final ValueNotifier<Locale?> notifier = ValueNotifier<Locale?>(null);

  // Called once before runApp() so the very first frame already
  // renders in the saved language instead of flashing English first.
  static Future<void> loadSaved() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString(_prefsKey);
    if (saved != null && kSupportedLanguages.any((l) => l.code == saved)) {
      notifier.value = Locale(saved);
    }
  }

  static Future<void> setLocale(String code) async {
    notifier.value = Locale(code);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefsKey, code);
  }
}
