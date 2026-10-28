Save & Send 1.3.2 is a small follow-up to 1.3.1. It fixes the last piece of
download-flavoured wording left on the Status screen and ships a newer yt-dlp.

## What changed

**The cancel dialog matches the screen.** While a Status action is encoding, the
confirmation now says **Stop this Status action?** and **The new copy will not be
saved.** The dismiss button reads **Keep going**. Previously it asked whether to
stop a download and warned that the video would not be saved — which was both
confusing and wrong, since the original video was already in the Gallery.

**Bundled yt-dlp is now 2026.10.26.** The extractor fixes from the last week are
included, which matters most for YouTube. As before, Settings → **Downloader
updates** can pull a newer engine without waiting for an APK.

**The engine version can no longer drift.** The startup check now compares the
zipapp in the APK with the copy on disk, and a new test fails the build when the
version constant, the zipapp, and the release checklist disagree. That is how
the bundled copy went stale between releases.

## Install

1. Download `SaveAndSend-v1.3.2-arm64.apk`.
2. Optionally verify the SHA-256 checksum below.
3. Install over 1.3.1. Uninstall first only if your copy was signed with a
   different key.

Gallery files, Recent, language, and Wi-Fi preference are kept.
