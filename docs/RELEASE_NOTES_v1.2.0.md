Save & Send 1.2.0 is the everyday pack. The downloader now tells you what a link
will cost before you commit to it, saves the soundtrack when you only want the
audio, names the file after the video, and keeps a Recent shelf so you can send
something again without opening the Gallery.

## What's new

**Pick before you download.** Paste a link and the app reads its title, length,
and the estimated size of every quality up to 1080p, plus sound-only. The chosen
height goes straight to the downloader, so a 480p tap really is a 480p file.

**Sound only.** Saves a 192 kbps MP3 into `Music/Save & Send`. It is shared as
`audio/mpeg`, so voice notes and music land in the right place.

**Real filenames.** The Gallery entry, the share name, and Recent use the video
title. WhatsApp now shows "A calm evening by the sea", not
`SaveAndSend_20261028_120000.mp4`.

**Clipboard hand-off.** If a supported link is already on the clipboard, the
home screen offers it. It never starts on its own, and tapping "Not now" is
remembered for that link.

**Recent.** The last 30 downloads with a thumbnail, size, and date. Open,
re-send, or delete from the sheet. Entries point at the Gallery copy, so clearing
the cache cannot break them.

**Wi-Fi only.** Big downloads wait for Wi-Fi and say why instead of failing
halfway.

**When a site breaks.** The error screen can retry with another player client.
Troubleshooting runs a redacted link check you can copy into an issue, and
Settings can switch the downloader between Stable and Nightly.

**More places work.** Reddit `/s/` share links are resolved before download, and
bare links from Vimeo, Dailymotion, Twitch, Reddit, Pinterest, SoundCloud,
Bilibili, and other yt-dlp sites are recognised without typing `https://`.

## Also improved

- Success and error haptics.
- Sharing and deleting use the MediaStore URI instead of a rotating cache path.
- History thumbnails are copied into app storage and pruned to the newest 60.
- A failed Gallery save still keeps the result screen and the file name intact.

## Install

1. Download `SaveAndSend-v1.2.0-arm64.apk`.
2. Optionally verify the SHA-256 checksum.
3. Install over 1.1.1. If you installed an older build signed with a different
   key, uninstall it first.

## Release integrity

| | |
| --- | --- |
| APK | `SaveAndSend-v1.2.0-arm64.apk` |
| SHA-256 | `3c7ba00d604bce7521165b3a5b40a40289f1eaeaebbbd70e54bacc7afbac5813` |
| Signing certificate SHA-256 | `F7:DB:E1:CD:37:9F:83:AA:78:05:C8:6E:1C:6B:B7:F4:8D:C0:43:CF:9B:F3:A5:30:C8:EB:B2:8A:8A:61:F1:82` |
| Version | 1.2.0 (5) |
| Min SDK | 24 |
| ABI | `arm64-v8a` |

## Full changelog

[CHANGELOG.md](https://github.com/AdilSiddiquiHQ/save-and-send/blob/main/CHANGELOG.md)
