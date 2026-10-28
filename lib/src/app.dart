import 'package:flutter/material.dart';

import 'home_screen.dart';
import 'i18n.dart';
import 'native.dart';
import 'theme.dart';

class SaveAndSendApp extends StatefulWidget {
  const SaveAndSendApp({super.key, this.initialLanguage = 'en'});

  final String initialLanguage;

  @override
  State<SaveAndSendApp> createState() => _SaveAndSendAppState();
}

class _SaveAndSendAppState extends State<SaveAndSendApp> {
  late String _lang = AppLanguage.supports(widget.initialLanguage)
      ? widget.initialLanguage
      : 'en';

  void _setLanguage(String lang) {
    if (!AppLanguage.supports(lang) || lang == _lang) return;
    setState(() => _lang = lang);
    NativeBridge.setPref('lang', lang).catchError((Object _) {});
  }

  @override
  Widget build(BuildContext context) {
    final locale = Locale(_lang);
    return MaterialApp(
      onGenerateTitle: (context) => AppLocalizations.of(context).appName,
      debugShowCheckedModeBanner: false,
      theme: buildTheme(language: _lang),
      locale: locale,
      supportedLocales: AppLocalizations.supportedLocales,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      home: HomeScreen(
        strings: lookupAppLocalizations(locale),
        language: _lang,
        onLanguageChanged: _setLanguage,
      ),
    );
  }
}
