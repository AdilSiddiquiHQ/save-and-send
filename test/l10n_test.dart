import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Guards the ARB files that `flutter gen-l10n` turns into `AppLocalizations`.
///
/// A missing key does not fail the generator, it silently falls back to
/// English. These tests make that a build error instead.
void main() {
  const directory = 'lib/l10n';
  const templatePath = '$directory/app_en.arb';

  Map<String, dynamic> read(String path) {
    final file = File(path);
    expect(file.existsSync(), isTrue, reason: 'Missing $path');
    return jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
  }

  Set<String> messages(Map<String, dynamic> arb) {
    return arb.keys.where((key) => !key.startsWith('@')).toSet();
  }

  Set<String> placeholders(Object? message) {
    return RegExp(r'\{(\w+)\}')
        .allMatches(message! as String)
        .map((match) => match.group(1)!)
        .toSet();
  }

  // Only file names are collected here; the JSON is read inside tests because
  // `expect` is not allowed while the suite is being registered.
  final paths = Directory(directory)
      .listSync()
      .whereType<File>()
      .map((file) => file.path)
      .where((path) => path.endsWith('.arb'))
      .toList()
    ..sort();

  test('the template is not empty and fully filled in', () {
    final template = read(templatePath);
    final keys = messages(template);
    expect(keys, isNotEmpty);
    for (final key in keys) {
      expect(
        (template[key] as String).trim(),
        isNotEmpty,
        reason: 'app_en.arb has an empty "$key"',
      );
    }
  });

  test('there is one ARB file per shipped language', () {
    expect(paths.length, greaterThanOrEqualTo(2));
    for (final path in paths) {
      final name = path.split('/').last;
      final arb = read(path);
      final locale = arb['@@locale'];
      expect(locale, isA<String>());
      expect(name, 'app_$locale.arb');
    }
  });

  for (final path in paths) {
    final name = path.split('/').last;
    if (name == 'app_en.arb') continue;

    group(name, () {
      late Map<String, dynamic> template;
      late Map<String, dynamic> arb;
      late String locale;

      setUp(() {
        template = read(templatePath);
        arb = read(path);
        locale = arb['@@locale'] as String;
      });

      test('has exactly the template keys', () {
        expect(
          messages(template).difference(messages(arb)),
          isEmpty,
          reason: 'Untranslated in $locale',
        );
        expect(
          messages(arb).difference(messages(template)),
          isEmpty,
          reason: 'Unknown keys in $locale',
        );
      });

      test('has no empty message', () {
        for (final key in messages(arb)) {
          expect(
            (arb[key] as String).trim(),
            isNotEmpty,
            reason: '$locale has an empty "$key"',
          );
        }
      });

      test('keeps the template placeholders', () {
        for (final key in messages(template)) {
          expect(
            placeholders(arb[key]),
            placeholders(template[key]),
            reason: '$locale changes the placeholders in "$key"',
          );
        }
      });

      test('is actually translated, not copied from English', () {
        // Brand name and sample URL are intentionally language-neutral.
        const shared = {'appName', 'pasteHint'};
        final copied = messages(arb)
            .where((key) => arb[key] == template[key])
            .toSet()
            .difference(shared);
        expect(copied, isEmpty, reason: '$locale still has English text');
      });
    });
  }
}
