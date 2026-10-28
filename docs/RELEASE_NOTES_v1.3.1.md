Save & Send 1.3.1 is a hardening release. Nothing new to learn: the Status
tools now refuse to do pointless work, the cache has a ceiling, and cookies are
encrypted at rest. It also closes the gaps that made bugs hard to catch.

## What changed

**The Status tools stop when they would change nothing.** Fit is disabled on a
clip that is already 9:16, Split on a clip under 59.5 seconds, Trim on anything
shorter than two seconds, and Make smaller on a file already 8 MB or less. Each
row says why instead of running a full re-encode that loses quality and produces
the same file.

**The card warns about re-encoding.** One line: these re-encode the clip, so the
picture softens a little each time. That is the sentence that stops someone
shrinking the same video three times.

**Trim has a preview.** The range slider shows a frame at the start handle, so
you can see the moment you are keeping instead of reading timestamps.

**Storage is visible and clearable.** Settings → Storage shows what downloads,
Status copies, and preview frames are using, with one clear button. The Status
cache is also capped at 250 MB now, oldest outputs first. Gallery files are
never touched. The folder holding the file you are working on is never deleted —
that was a real bug when applying a second tool to a part.

**Cookies are encrypted.** They live in `filesDir/cookies.enc` under an
AES-GCM key in the Android Keystore. A plaintext copy appears in the cache only
while a request runs and is deleted when it ends. An existing
`cookies.txt` is encrypted and removed on first launch.

**Plain HTTP is blocked.** `android:usesCleartextTraffic="false"` plus a network
security config, so no future change can quietly downgrade a download.

**The encoding screen speaks the right language.** It says For Status, not
Download, and the cancel button no longer talks about downloads.

## Under the hood

- 23 new JVM tests cover splitting, the bitrate budget, FFmpeg argument order,
  and cache pruning. The 1.3.0 source-deletion bug now has a regression test.
- `tool/release.sh` builds, verifies the signature, checks the 68 MiB budget and
  the arm64-only ABI, writes the checksums and an SBOM, then tags and publishes.
- CI runs the Kotlin tests, a check that every translation key actually reaches
  the UI, and a release build with the same size and ABI limits.
- Dependabot watches Actions and Gradle, and a monthly job opens an issue when
  the bundled yt-dlp falls behind upstream.

## Install

1. Download `SaveAndSend-v1.3.1-arm64.apk`.
2. Optionally verify the SHA-256 checksum below.
3. Install over 1.3.0. If you installed a build signed with a different key,
   uninstall it first — Android will not update across a key change.

Your Gallery files, Recent list, language, and Wi-Fi preference are kept.
