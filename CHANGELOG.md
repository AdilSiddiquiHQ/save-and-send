# Changelog

All notable changes to Save & Send are documented here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and the project uses
[Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [1.3.1] — 2026-10-28

### Added

- **Trim preview.** The range slider now shows a frame at the start handle, so
  the cut is chosen by picture instead of by guessing from the time.
- **Storage section in Settings.** Shows what downloads, Status copies, and
  preview frames are using, with a one-tap **Clear**. Gallery copies are never
  touched.
- JVM tests for the Status logic: split count, bitrate budget, FFmpeg argument
  order, and cache pruning (23 tests, no device needed).
- Release tooling: `tool/release.sh`, a CycloneDX SBOM per release,
  `docs/RELEASING.md`, issue and pull-request templates, Dependabot for Actions
  and Gradle, and a monthly yt-dlp check.
- CI now runs the Kotlin tests, a translation reachability check, and a release
  build that must stay under 68 MiB with only `arm64-v8a` libraries.
- `PRIVACY.md`, plus README sections for build prerequisites, permissions,
  file locations, upgrade and downgrade, broken-link reports, and an FAQ.

### Changed

- Status tools that would change nothing are disabled with a one-line reason:
  Fit on an already-9:16 clip, Split on a clip under 59.5 s, Trim on a clip
  under two seconds, and Make smaller on a file already 8 MB or less.
- The Status card says plainly that every action re-encodes the clip and that
  the picture softens a little each time.
- The encoding screen uses the Status wording instead of the download eyebrow
  and cancel copy.
- The transform cache is capped at 250 MB instead of growing until the next
  transform. Oldest outputs are pruned first; the folder holding the current
  input is preserved.
- The Kotlin pipeline builds FFmpeg commands through `TransformPlanner`, so the
  same code is exercised by tests and by the app.

### Fixed

- Applying a second Status tool to an output could delete the folder that held
  its own input. The source folder is now excluded from pruning and covered by
  a regression test.

### Security

- Login cookies are encrypted at rest with an AES-GCM key in the Android
  Keystore (`filesDir/cookies.enc`). The plaintext file exists only in the
  cache while a request runs.
- `android:usesCleartextTraffic="false"` and a network security config block
  plain HTTP, so no future code path can silently downgrade a download.

## [1.3.0] — 2026-10-28

### Added

- **For Status tools.** A card on the result screen with four one-tap fixes:
  - **Fit to Status** pads a landscape or square clip into 1080 × 1920 with a
    blurred copy of the same frame behind it. Nothing is cropped.
  - **Split into parts** cuts a long clip into 59.5-second pieces, names them
    `Title · 1`, `Title · 2`, and lists every part so they can be sent in order.
  - **Trim** opens a range slider over the whole clip, capped at 59.5 seconds,
    so a 3-minute video can keep its middle 40 seconds.
  - **Make smaller** re-encodes to an 8, 16, or 24 MB target with a bitrate
    budget, retrying once at a lower bitrate if the first pass overshoots.
- Every Status output is saved to the Gallery on its own, added to Recent with
  the same thumbnail as the source, and can be shared straight from its part
  row.
- Progress for encoding, with the same cancel path as a download.

### Changed

- Recent ids include the output path, so several parts saved in the same
  millisecond stay separate entries.
- A failed Status encode returns to the result screen with a short message
  instead of replacing the finished download with an error page.

### Fixed

- Trim and split keep the original orientation and only touch the duration;
  the resolution is left alone because the download is already Status-safe.

## [1.2.0] — 2026-10-28

### Added

- **Quality and size before the download.** Pasting a link reads its title,
  length, and an estimated size for every height up to 1080p, plus sound-only.
  The chosen height is passed straight to yt-dlp, so a 480p tap really is a
  480p download.
- **Sound only.** Saves a 192 kbps MP3 through the bundled LAME encoder, into
  `Music/Save & Send`, shared as `audio/mpeg`.
- **Real filenames.** The Gallery entry, the share name, and Recent use the
  video title. No more `SaveAndSend_20261028_120000.mp4`.
- **Clipboard detection.** A supported link already on the clipboard is offered
  on the home screen. It never downloads on its own, and "Not now" is remembered
  for that link.
- **Recent downloads.** The last 30 files with a thumbnail, size, and date, plus
  open, re-send, delete, and clear. Entries point at the Gallery copy, so cache
  cleanup cannot break them.
- **Wi-Fi only.** Holds a download until Wi-Fi is available and says so instead
  of failing halfway.
- **Try another method.** The error screen can rerun the link with a different
  player client and format ladder.
- **Link check.** Troubleshooting runs `yt-dlp --simulate --verbose`, redacts
  app paths and cookie lines, and lets you copy the report.
- **Engine channel picker.** Stable or Nightly, applied to the next update.
- Success and error haptics.
- Reddit `/s/` share links are resolved before download, and bare links from
  Vimeo, Dailymotion, Twitch, Reddit, Pinterest, SoundCloud, Bilibili, and other
  yt-dlp sites are recognised without typing `https://`.

### Changed

- Gallery saves return a MediaStore URI; opening, re-sharing, and deleting use
  that URI instead of the rotating download cache.
- The composer hint now reads "MP4 or MP3".
- The home header has a Recent button with an unread dot when the list is not
  empty.
- History thumbnails are copied into app storage and pruned to the newest 60.

### Fixed

- A failed Gallery save no longer loses the file name or the result entry.
- Audio-only downloads skip the video transcode path, which was wasted work.

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
