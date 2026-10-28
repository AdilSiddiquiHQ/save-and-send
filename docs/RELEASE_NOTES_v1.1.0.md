Save & Send now speaks five languages. That is the whole release: the download
pipeline is unchanged from 1.0.1.

## New languages

- **हिन्दी (Hindi)**
- **العربية (Arabic)** — full right-to-left layout
- **বাংলা (Bengali)**

English and اردو are still there, and the language picker now shows every
language in its own script. The choice is saved and applied before the first
frame, so an Arabic or Urdu screen does not flash English on launch.

## How the translations were written

These are not word-for-word renderings. Each screen was rewritten in the register
people actually use in a phone app — English loanwords kept where they are the
natural word (*link*, *save*, *download*, *status*), no textbook constructions,
and shorter lines so buttons and chips do not overflow.

Two layout fixes came out of it:

- Arabic and Urdu text no longer gets letter spacing, which was pulling joined
  letters apart.
- URLs and native error logs stay left to right inside right-to-left screens.

## Please read your language

Hindi, Arabic, and Bengali are a first pass. If something sounds off to you, the
fastest fix is an issue with the exact string and what you would say instead.
The glossary and tone rules live in
[`docs/TRANSLATIONS.md`](https://github.com/AdilSiddiquiHQ/save-and-send/blob/main/docs/TRANSLATIONS.md).

## Under the hood

- Moved to Flutter's `gen_l10n`: one ARB file per language in `lib/l10n/`.
- Added `test/l10n_test.dart`, which fails when a language is missing a key, has
  an empty message, drops a `{time}` placeholder, or still contains English.
- Settings footer version now comes from one constant instead of a hand-edited
  string.

## Install

1. Download `SaveAndSend-v1.1.0-arm64.apk`.
2. Optionally verify the SHA-256 checksum.
3. Install over 1.0.1. If you installed an older build signed with a different
   key, uninstall it first.

## Release integrity

| | |
| --- | --- |
| APK | `SaveAndSend-v1.1.0-arm64.apk` |
| SHA-256 | `568f6d9341ff79d7a7494c0bc577f4bf8b34b0017a07b2ea120c5830bc770a03` |
| Signing certificate SHA-256 | `F7:DB:E1:CD:37:9F:83:AA:78:05:C8:6E:1C:6B:B7:F4:8D:C0:43:CF:9B:F3:A5:30:C8:EB:B2:8A:8A:61:F1:82` |
| Version | 1.1.0 (3) |
| Min SDK | 24 |
| ABI | `arm64-v8a` |

## Full changelog

[CHANGELOG.md](https://github.com/AdilSiddiquiHQ/save-and-send/blob/main/CHANGELOG.md)
