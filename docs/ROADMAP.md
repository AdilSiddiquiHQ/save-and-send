# Roadmap

This is a working list, ordered by how much it improves the app for the person
actually using it. Everything here is a candidate, not a promise: the app is a
personal tool and features are added when they earn their maintenance cost.

Effort is a rough shape, not a schedule: **S** (an afternoon), **M** (a few
sessions), **L** (a week or more).

## Shipped in 1.2.0

The everyday pack: quality and size before download, sound-only MP3, real
filenames, clipboard detection, a Recent sheet, Wi-Fi only, "try another
method", a redacted link check, the engine channel picker, and a wider set of
recognised sites. The Status encode tools (fit to 9:16, split into 60-second
parts, trim, compress to a target) are the next release.

## 1. Reliability — the downloads have to work

| Idea | Why it matters | Effort |
| --- | --- | --- |
| **Engine diagnostics screen** | *(Shipped in 1.2.0)* Runs `yt-dlp --simulate --verbose` and shows a copyable, redacted log. | M |
| **Engine channel picker** | *(Shipped in 1.2.0)* Stable or Nightly for the bundled downloader. | S |
| **Per-site cookie profiles** | Separate cookie jars for YouTube, Instagram, Facebook, and TikTok instead of one shared file. Logging into one does not disturb the others. | M |
| **Cookie import from a file** | Pick a `cookies.txt` with the system file picker instead of pasting it. The pasted path stays available. | S |
| **Encrypted cookie storage** | Wrap the cookie file with an Android Keystore key so a backup or a rooted device cannot read it in plain text. | M |
| **Silent-video rescue** | *(Shipped in 1.0.1)* Mux a left-over audio stream back into the video when yt-dlp cannot merge. | S |
| **Preflight check** | Verify free space, network type, and engine health before starting, with a clear message instead of a mid-download failure. | S |
| **Retry with a different strategy** | *(Shipped in 1.2.0)* One tap reruns the last link with another player client and format ladder. | S |
| **Resume after the app is killed** | Keep the partial download and continue on the next launch instead of discarding it. | L |

## 2. Everyday use

| Idea | Why it matters | Effort |
| --- | --- | --- |
| **Download queue** | Share or paste several links and let them run one after another. Currently a second share is held in memory and lost on exit. | M |
| **Recent downloads list** | *(Shipped in 1.2.0)* Re-share or delete something saved earlier without hunting through Gallery. | M |
| **Trim editor** | Pick a start and end point, or send the full video without the 59.5-second cut. | L |
| **Quality picker** | *(Shipped in 1.2.0)* Heights from 1080p down, with estimated sizes. | S |
| **Audio-only export** | *(Shipped in 1.2.0 as MP3)* Save the soundtrack for voice notes and music. | S |
| **Wi-Fi-only downloads** | *(Shipped in 1.2.0)* Refuses to start on mobile data and says why. | S |
| **Clipboard detection** | *(Shipped in 1.2.0)* Offers the copied link without ever starting on its own. | S |
| **Duplicate detection** | Warn when the same video was saved before. | S |
| **Cache size and cleanup** | Show what the working files use and clear them in one tap. | S |
| **Filename control** | *(Shipped in 1.2.0: title)* Still open: timestamp or original name as a preference. | S |
| **Dark theme and Material You** | The palette is light-only today. Dynamic color on Android 12+. | M |
| **Quick Settings tile / home widget** | Paste and download without opening the app. | M |
| **Tablet and foldable layout** | Two-pane composer and preview on large screens. | M |

## 3. Sharing

| Idea | Why it matters | Effort |
| --- | --- | --- |
| **Direct Share targets** | Put frequent WhatsApp chats at the top of the system share sheet. | M |
| **Accept shared video files** | Handle `video/*` shares, not only `text/*`, so a forwarded video can be re-sent optimized. | S |
| **Status trim presets** | 15 s, 30 s, 59.5 s, or full length. | S |
| **Share the original link too** | One action to send the cleaned-up URL alongside the file. | S |
| **"Save to Gallery" on the result screen** | *(Exists as a retry)* Make it explicit even when the first save succeeded. | S |

## 4. Trust and operations

| Idea | Why it matters | Effort |
| --- | --- | --- |
| **Redacted log export** | *(Shipped in 1.2.0)* Paths and cookie lines are stripped, then copied in one tap. | S |
| **App lock** | Optional biometric gate; the Gallery copy stays protected by Android anyway. | M |
| **In-app update check** | Compare against GitHub releases, verify the APK signature, then hand off to the installer. | L |
| **F-Droid / IzzyOnDroid metadata** | A second install path for people who do not sideload from GitHub. | M |
| **Obtainium-friendly releases** | Keep the release asset names stable so Obtainium can track updates. | S |

## 5. Deliberately not planned

- Playlists and channel downloads. One link, one video keeps the UI honest.
- Background downloads through a foreground service. The current design favors
  no permanent notification and no battery drain.
- DRM circumvention, private-content scraping, or anything that needs an
  account farm.
- Accounts, syncing, telemetry, or a server of any kind.

## Languages

The interface ships English, Urdu, Hindi, Arabic, and Bengali. Adding a language
is now one ARB file plus one entry in `AppLanguage.all`; it no longer means
editing Dart. See [`TRANSLATIONS.md`](TRANSLATIONS.md) for the tone rules and the
glossary.

**Done in 1.1.0:** the move to Flutter's `gen_l10n` with one ARB file per
language, `flutter_localizations`, nullable-safe generated getters, and
`test/l10n_test.dart`, which fails when a key is missing, empty, or loses a
placeholder. The validator runs in CI.

### Tier 1 — highest reach for this app's use case

Chosen because these are the languages of the largest WhatsApp-Status-sharing
audiences, and the platforms involved (Instagram, TikTok, YouTube) are heavily
used there.

| Language | Code | Direction | Notes |
| --- | --- | --- | --- |
| Hindi | `hi` | LTR | **Shipped in 1.1.0** |
| Arabic | `ar` | RTL | **Shipped in 1.1.0** |
| Bengali | `bn` | LTR | **Shipped in 1.1.0** |
| Indonesian | `id` | LTR | Large TikTok audience |
| Turkish | `tr` | LTR | Large Instagram/YouTube audience |
| Spanish | `es` | LTR | Broad, including Latin America |
| Portuguese (Brazil) | `pt-BR` | LTR | Large short-video audience |
| Vietnamese | `vi` | LTR | Large TikTok/YouTube audience |
| Filipino | `fil` | LTR | Large Facebook/WhatsApp audience |
| Persian | `fa` | RTL | Shares the Arabic script and RTL work |

### Tier 2 — worthwhile once the pipeline is in place

| Language | Code | Direction |
| --- | --- | --- |
| Russian | `ru` | LTR |
| French | `fr` | LTR |
| German | `de` | LTR |
| Thai | `th` | LTR |
| Tamil | `ta` | LTR |
| Telugu | `te` | LTR |
| Malayalam | `ml` | LTR |
| Marathi | `mr` | LTR |
| Gujarati | `gu` | LTR |
| Kannada | `kn` | LTR |
| Punjabi (Gurmukhi) | `pa` | LTR |
| Punjabi (Shahmukhi) | `pa-PK` | RTL |
| Malay | `ms` | LTR |
| Swahili | `sw` | LTR |
| Italian | `it` | LTR |
| Dutch | `nl` | LTR |
| Polish | `pl` | LTR |
| Ukrainian | `uk` | LTR |
| Romanian | `ro` | LTR |
| Azerbaijani | `az` | LTR |

### Tier 3 — only with an active translator

Pashto (`ps`, RTL), Sindhi (`sd`, RTL), Uyghur (`ug`, RTL), Central Kurdish
(`ckb`, RTL), Hebrew (`he`, RTL), Greek (`el`), Czech (`cs`), Swedish (`sv`),
Danish (`da`), Finnish (`fi`), Norwegian (`nb`), Hungarian (`hu`), Bulgarian
(`bg`), Croatian (`hr`), Serbian (`sr`), Slovak (`sk`).

### Typography and layout notes

- The bundled Noto Sans Arabic already covers Urdu, Arabic, Persian, Pashto,
  Sindhi, and Uyghur. Do not bundle a font per script: Flutter falls back to the
  system font for Devanagari, Bengali, Tamil, Telugu, Malayalam, Thai, and
  Hebrew, which costs nothing in APK size.
- Every RTL language needs the screens reviewed at a large text scale, because
  the cards use directional padding in places.
- Language names in the picker should be written in their own script
  (`العربية`, `हिन्दी`, `বাংলা`, `فارسی`), not in English.
- Arabic-script locales must keep `letterSpacing` at zero; spacing separates the
  joined letters.
- Persist the choice per install and fall back to English for an unknown code.
