## What changed

<!-- One or two sentences. Link the issue if there is one. -->

## How it was checked

<!-- Pick what applies and say what you actually ran. -->

- [ ] `flutter analyze`
- [ ] `flutter test`
- [ ] `cd android && ./gradlew :app:testDebugUnitTest`
- [ ] `python3 tool/check_l10n.py`
- [ ] Installed on a phone and tried the affected flow

Device / Android version, if this touches native code:

## Checklist

- [ ] Strings are in `lib/l10n/app_en.arb` and reach the UI (`python3 tool/check_l10n.py` passes)
- [ ] Non-English text is natural, not a word-for-word translation
- [ ] No APK, keystore, password, cookie, or signing file is included
- [ ] Goldens regenerated if the UI changed (`flutter test --update-goldens test/visual_test.dart`)
- [ ] `README.md` / `CHANGELOG.md` updated if behaviour or settings changed
- [ ] Existing release assets were not replaced (a new version bumps `pubspec.yaml` and `lib/src/version.dart`)
