import 'package:flutter/material.dart';

import 'src/app.dart';
import 'src/i18n.dart';
import 'src/native.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Load the saved language before the first frame so an Urdu or Arabic user
  // does not see an English flash on every launch.
  var language = 'en';
  try {
    final saved = await NativeBridge.getPref('lang');
    if (saved != null && AppLanguage.supports(saved)) language = saved;
  } catch (_) {
    // English is the safe default.
  }

  runApp(SaveAndSendApp(initialLanguage: language));
}
