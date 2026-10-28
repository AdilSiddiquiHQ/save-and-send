import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

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
  late String _lang = widget.initialLanguage;

  void _setLanguage(String lang) {
    if (lang == _lang) return;
    setState(() => _lang = lang);
    NativeBridge.setPref('lang', lang).catchError((Object _) {});
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Save & Send',
      debugShowCheckedModeBanner: false,
      theme: buildTheme(language: _lang),
      locale: Locale(_lang),
      supportedLocales: const [Locale('en'), Locale('ur')],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      home: HomeScreen(
        strings: Strings(_lang),
        language: _lang,
        onLanguageChanged: _setLanguage,
      ),
    );
  }
}
