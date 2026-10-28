**Save any video. Send it in one tap.**

The first public release of Save & Send: a private, on-device Android app that
turns a shared Instagram, Facebook, YouTube, or TikTok link into a
WhatsApp-ready MP4.

## Highlights

- Share-sheet intake and a paste-a-link composer.
- On-device download with bundled yt-dlp 2026.10.21, Python, and FFmpeg.
- Automatic H.264/AAC normalization, `+faststart`, and a 1080p downscale when
  the source is larger than 1920 px.
- Automatic trim to the first 59.5 seconds for WhatsApp Status.
- Gallery save to `Movies/Save & Send/`.
- One-tap **Send on WhatsApp**, **Post to Status**, and **More apps**.
- Inline preview with play, pause, mute, and metadata.
- English and Urdu interfaces with RTL-aware typography.
- Built-in yt-dlp updater and optional login cookies.

## Install

1. Download `SaveAndSend-v1.0.0-arm64.apk` below.
2. Optionally verify the SHA-256 checksum.
3. Allow installs from your browser or file manager, then open the APK.
4. On first launch, wait 10–60 seconds while the bundled runtime extracts.
5. Share a link to Save & Send, or paste one into the composer.

If you installed an earlier build signed with a different key, uninstall it
first. Android will not update across signing certificates.

## Requirements

- Android 7.0 (API 24) or newer.
- `arm64-v8a` device.
- About 70 MB for the APK and roughly 300 MB free for first-run extraction.
- Internet access.
- WhatsApp optional.

## Release integrity

| | |
| --- | --- |
| APK | `SaveAndSend-v1.0.0-arm64.apk` |
| SHA-256 | `9da3c3fefb6f96070c2e74a20ecc80d4c63581ea84e2289767fe201dfb749f67` |
| Signing certificate SHA-256 | `F7:DB:E1:CD:37:9F:83:AA:78:05:C8:6E:1C:6B:B7:F4:8D:C0:43:CF:9B:F3:A5:30:C8:EB:B2:8A:8A:61:F1:82` |
| Version | 1.0.0 (1) |
| Min SDK | 24 |
| ABI | `arm64-v8a` |

Verify the download:

```bash
shasum -a 256 SaveAndSend-v1.0.0-arm64.apk
```

The APK is signed with the project's private release key. Future updates must
be signed with the same key.

## Known limitations

- `arm64-v8a` only.
- One download at a time; downloads stop if Android kills the activity.
- Public, non-DRM content only.
- Platform changes can break extraction until yt-dlp is updated from Settings.
- Some WhatsApp builds do not support the direct Status intent; the app falls
  back to the contact picker.

## Full changelog

[CHANGELOG.md](https://github.com/AdilSiddiquiHQ/save-and-send/blob/main/CHANGELOG.md)
