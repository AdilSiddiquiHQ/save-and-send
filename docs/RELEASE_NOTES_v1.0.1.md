A small reliability update: silent downloads are fixed, and YouTube gets one
more chance before it gives up.

## Fixed

- **Videos that arrived without sound.** When yt-dlp downloads video and audio
  as separate streams and its merge step does not finish, the app used to pick
  the video-only file and hand you a silent MP4. It now merges the left-over
  audio track with FFmpeg and checks that the result really contains audio
  before saving it.
- **YouTube player fallbacks.** A third player-client set (`tv_simply`,
  `web_embedded`, `mweb`) is attempted before a download is reported as
  blocked.
- **Clearer YouTube errors.** Signature (`nsig`) and player-extraction failures
  are now reported as a YouTube block with the right advice, instead of a
  generic "couldn't download" message.

## If YouTube still refuses

YouTube changes its player responses constantly. Two things help, in order:

1. Open **Settings → Downloader** and update the engine. This replaces the
   bundled yt-dlp without reinstalling the app.
2. If a specific video needs a session, add cookies in **Settings → Cookies**.

If it still fails, open the error's **Details** and share that text — it says
exactly which step failed.

## Install

1. Download `SaveAndSend-v1.0.1-arm64.apk`.
2. Optionally verify the SHA-256 checksum.
3. Install over 1.0.0. If 1.0.0 was installed from a different signing key,
   uninstall it first.

## Release integrity

| | |
| --- | --- |
| APK | `SaveAndSend-v1.0.1-arm64.apk` |
| SHA-256 | `6f752f78224c9bd06e2eb3a3b393db894a9a0607753559abeffd02a238578949` |
| Signing certificate SHA-256 | `F7:DB:E1:CD:37:9F:83:AA:78:05:C8:6E:1C:6B:B7:F4:8D:C0:43:CF:9B:F3:A5:30:C8:EB:B2:8A:8A:61:F1:82` |
| Version | 1.0.1 (2) |
| Min SDK | 24 |
| ABI | `arm64-v8a` |

## Full changelog

[CHANGELOG.md](https://github.com/AdilSiddiquiHQ/save-and-send/blob/main/CHANGELOG.md)
