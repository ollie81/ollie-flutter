import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

// flutter_localizations doesn't ship Kinyarwanda ('rw') -- it's missing
// from kMaterialSupportedLanguages, kCupertinoSupportedLanguages and
// kWidgetsSupportedLanguages alike, unlike the other 9 languages in
// kSupportedLanguages, which are all in every one of those sets. Left
// alone, that makes GlobalMaterialLocalizations.delegate (and the
// Cupertino/Widgets equivalents) report isSupported(rw) == false, so
// Localizations skips them entirely for that locale and any widget
// that needs one throws "No MaterialLocalizations found" -- rendered
// as a blank ErrorWidget box in release builds (TextField, dialogs,
// tooltips, Scrollbar...). These three delegates claim 'rw' so that
// never happens, and just serve the English strings/formatting for
// Flutter's own built-in widget text; every actual app string still
// comes from AppLocalizations, which does support 'rw' natively.
const List<String> _kMissingFromFlutter = <String>['rw'];

class FallbackMaterialLocalizationsDelegate
    extends LocalizationsDelegate<MaterialLocalizations> {
  const FallbackMaterialLocalizationsDelegate();

  @override
  bool isSupported(Locale locale) =>
      _kMissingFromFlutter.contains(locale.languageCode);

  @override
  Future<MaterialLocalizations> load(Locale locale) =>
      GlobalMaterialLocalizations.delegate.load(const Locale('en'));

  @override
  bool shouldReload(FallbackMaterialLocalizationsDelegate old) => false;
}

class FallbackCupertinoLocalizationsDelegate
    extends LocalizationsDelegate<CupertinoLocalizations> {
  const FallbackCupertinoLocalizationsDelegate();

  @override
  bool isSupported(Locale locale) =>
      _kMissingFromFlutter.contains(locale.languageCode);

  @override
  Future<CupertinoLocalizations> load(Locale locale) =>
      GlobalCupertinoLocalizations.delegate.load(const Locale('en'));

  @override
  bool shouldReload(FallbackCupertinoLocalizationsDelegate old) => false;
}

class FallbackWidgetsLocalizationsDelegate
    extends LocalizationsDelegate<WidgetsLocalizations> {
  const FallbackWidgetsLocalizationsDelegate();

  @override
  bool isSupported(Locale locale) =>
      _kMissingFromFlutter.contains(locale.languageCode);

  @override
  Future<WidgetsLocalizations> load(Locale locale) =>
      GlobalWidgetsLocalizations.delegate.load(const Locale('en'));

  @override
  bool shouldReload(FallbackWidgetsLocalizationsDelegate old) => false;
}
