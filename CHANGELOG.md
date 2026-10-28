# Changelog

All notable changes to Save & Send are documented here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and the project uses
[Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [1.1.1] — 2026-10-28

### Fixed

- The selected language chip in Settings drew its label at the top of the chip
  instead of centring it, which made "English" sit visibly higher than the rest
  of the row.

## [1.1.0] — 2026-10-28

### Added

- Hindi, Arabic, and Bengali interfaces. The app now ships English, Urdu,
  Hindi, Arabic, and Bengali, selectable in Settings.
- `gen_l10n` pipeline: one ARB file per language in `lib/l10n/`, a template
  file, and a test that fails when a key, an empty message, or a `{time}`
  placeholder is missing.
- [`docs/TRANSLATIONS.md`](docs/TRANSLATIONS.md) with the tone rules, a per-app
  glossary, the review status of each language, and the steps for adding one.
- Arabic layout mirroring is now exercised by a golden screenshot and by an
  RTL assertion in the widget tests.

### Changed

- The language picker shows every language in its own script and wraps onto a
  second row instead of being a two-way switch.
- The URL field and native log text are always left to right, so a URL or an
  error log is not reordered inside an Arabic or Urdu screen.
- Arabic-script locales set `letterSpacing` to zero; spacing between letters
  broke the joins in Arabic and Urdu text.
- The settings footer reads the version from `lib/src/version.dart` instead of a
  hardcoded string.

## [1.0.1] — 2026-10-28

### Fixed

- Videos whose audio track arrived as a separate stream are now muxed back
  instead of being returned silent. When yt-dlp cannot finish its own merge,
  the downloader merges the left-over video and audio files with FFmpeg and
  verifies that the result really contains sound.
- YouTube downloads try one more player-client set (`tv_simply`,
  `web_embedded`, `mweb`) before giving up, which recovers some videos that the
  earlier clients refuse.
- Signature (`nsig`) and player-extraction failures are now reported as a
  YouTube block instead of a generic error, so the suggested fix matches the
  actual problem.

## [1.0.0] — 2026-10-28

### Added

- Share-sheet intake for public Instagram, Facebook, YouTube, TikTok, and other
  yt-dlp-supported links.
- On-device download pipeline with bundled yt-dlp 2026.10.21, Python, and
  FFmpeg.
- Automatic H.264/AAC MP4 normalization, 1080p cap, and `+faststart` output.
- Automatic trim to the first 59.5 seconds for WhatsApp Status.
- Gallery save through MediaStore on Android 10+ and direct Movies storage on
  Android 7–9.
- One-tap **Send on WhatsApp**, **Post to Status**, and **More apps** actions.
- In-app preview with play, pause, mute, and metadata.
- English and Urdu interfaces with RTL-aware typography.
- Built-in yt-dlp updater and optional Netscape-format login cookies.
- Warm alabaster/sage visual system with Manrope, Plus Jakarta Sans, Noto Sans
  Arabic, and Lucide icons.
- Responsive layouts and golden coverage for idle, result, settings, and Urdu
  screens.

### Known limitations

- arm64-v8a devices only.
- One download at a time; downloads run while the app is open, not as a
  foreground service.
- Public, non-DRM content only. Private, age-restricted, or login-gated videos
  need cookies and may still be refused by the platform.
- WhatsApp Status deep linking depends on the installed WhatsApp version; older
  builds fall back to the contact picker.

[1.0.0]: https://github.com/AdilSiddiquiHQ/save-and-send/releases/tag/v1.0.0
