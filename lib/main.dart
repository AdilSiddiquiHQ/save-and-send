import 'package:flutter/material.dart';

import 'src/app.dart';
import 'src/native.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Load the saved language before the first frame so an Urdu user does not
  // see an English flash on every launch.
  var language = 'en';
  try {
    final saved = await NativeBridge.getPref('lang');
    if (saved == 'en' || saved == 'ur') language = saved!;
  } catch (_) {
    // English is the safe default.
  }

  runApp(SaveAndSendApp(initialLanguage: language));
}
