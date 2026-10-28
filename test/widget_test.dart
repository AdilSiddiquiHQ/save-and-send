import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:save_and_send/src/i18n.dart';

void main() {
  AppLocalizations load(String code) {
    return lookupAppLocalizations(Locale(code));
  }

  test('the app name is a brand name in every language', () {
    for (final language in AppLanguage.all) {
      expect(load(language.code).appName, 'Save & Send');
    }
  });

  test('English strings resolve', () {
    final strings = load('en');
    expect(strings.appName, 'Save & Send');
    expect(strings.errPrivate, isNot('errPrivate'));
    expect(strings.errorFor('network'), contains('internet'));
    expect(strings.errorFor('nonsense'), isNull);
    expect(strings.stageFor('merging'), 'Adding sound…');
  });

  test('Urdu strings resolve and stay right to left', () {
    final strings = load('ur');
    expect(strings.download, 'ویڈیو ڈاؤن لوڈ کریں');
    expect(strings.stageFor('saving'), 'گیلری میں محفوظ کیا جا رہا ہے…');
    expect(AppLanguage.isRightToLeft('ur'), isTrue);
    expect(AppLanguage.isRightToLeft('hi'), isFalse);
  });

  test('every shipped language formats the time left', () {
    for (final language in AppLanguage.all) {
      expect(load(language.code).timeLeft('0:45'), contains('0:45'));
    }
  });

  test('unknown language codes fall back to English', () {
    expect(AppLanguage.byCode('xx').code, 'en');
    expect(AppLanguage.supports('xx'), isFalse);
  });
}
