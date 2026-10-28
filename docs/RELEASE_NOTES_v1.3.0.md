Save & Send 1.3.0 adds the part most downloaders skip: getting the file into
WhatsApp Status. The result screen now has a **For Status** card that can fit,
split, trim, or shrink the clip on the phone, without uploading it anywhere.

## What's new

**Fit to Status.** A landscape or square video is placed on a 1080 × 1920
canvas over a blurred copy of the same frame. The whole picture stays visible;
nothing is cropped or stretched.

**Split into parts.** Anything longer than 59.5 seconds becomes numbered parts:
`Title · 1`, `Title · 2`, and so on. Every part is saved to the Gallery and
listed on the result screen, so the second and third pieces are one tap away.

**Trim.** A range slider over the whole clip, capped at 59.5 seconds. A
three-minute video can keep its middle forty seconds instead of only the
opening.

**Make smaller.** Re-encodes to an 8, 16, or 24 MB target with a bitrate
budget. If the first pass overshoots, it retries once at a lower bitrate. The
resolution is left alone because the download is already Status-safe.

**Every output is a real file.** Each part gets its own Gallery entry, its own
Recent row with the source thumbnail, and its own share buttons. Encoding shows
progress and uses the same cancel path as a download.

## Also improved

- A failed Status encode returns to the finished download with a short message
  instead of replacing it with an error page.
- Split outputs get unique Recent ids, so several parts saved at once never
  overwrite each other.
- The part list shows duration and size per piece for a quick check before
  sending.

## Install

1. Download `SaveAndSend-v1.3.0-arm64.apk`.
2. Optionally verify the SHA-256 checksum.
3. Install over 1.2.0. If you installed an older build signed with a different
   key, uninstall it first.

## Release integrity

| | |
| --- | --- |
| APK | `SaveAndSend-v1.3.0-arm64.apk` |
| SHA-256 | `d61733c9477507dede2a4808be4049be7af5135707abb56a5e12ec3a53e0cb7e` |
| Signing certificate SHA-256 | `F7:DB:E1:CD:37:9F:83:AA:78:05:C8:6E:1C:6B:B7:F4:8D:C0:43:CF:9B:F3:A5:30:C8:EB:B2:8A:8A:61:F1:82` |
| Version | 1.3.0 (6) |
| Min SDK | 24 |
| ABI | `arm64-v8a` |

## Full changelog

[CHANGELOG.md](https://github.com/AdilSiddiquiHQ/save-and-send/blob/main/CHANGELOG.md)
