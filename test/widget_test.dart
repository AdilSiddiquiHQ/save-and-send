import 'package:flutter_test/flutter_test.dart';
import 'package:save_and_send/src/i18n.dart';

void main() {
  test('English strings are complete', () {
    const strings = Strings('en');
    expect(strings.t('appName'), 'Save & Send');
    expect(strings.t('err_private'), isNot('err_private'));
    expect(strings.errorFor('network'), contains('internet'));
  });

  test('Urdu strings fall back to English when a key is missing', () {
    const strings = Strings('ur');
    expect(strings.t('appName'), 'Save & Send');
    expect(strings.t('download'), 'ویڈیو ڈاؤن لوڈ کریں');
  });
}
