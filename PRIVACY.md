# Privacy Policy

**Save & Send** is an Android app that downloads a public video link you provide
and saves the result to your phone. This policy describes the current release.
Last updated: 28 October 2026.

## Summary

The app has no accounts, no ads, no analytics, no crash reporting, and no
server of its own. Nothing is collected, sold, or shared. The only network
traffic is the request to the site you paste, made from your phone.

## What the app stores

All of it stays on your device.

| Data | Location | Why |
| --- | --- | --- |
| Downloaded videos and MP3s | `Movies/Save & Send/` and `Music/Save & Send/` through Android MediaStore | The file you asked for |
| Recent list | App-private preferences (`SharedPreferences`) | Show what you downloaded before |
| Settings (language, Wi-Fi only, engine channel) | App-private preferences | Remember your choices |
| Login cookies, if you paste them | `filesDir/cookies.enc`, encrypted with a key in the Android Keystore | Let yt-dlp open a post that needs a logged-in session |
| Working files | App cache (`downloads/`, `transforms/`, `frames/`) | Downloading, re-encoding, thumbnails |

Nothing in that table is backed up: the app sets `android:allowBackup="false"`.
Uninstalling removes the Recent list, settings, cookies, and cache. Files
already saved to the Gallery stay.

Settings → **Storage** shows the cache size and clears it. Clearing the cache
never touches the Gallery.

## Network requests

When you download something, the app connects directly to the site hosting the
video (for example Instagram, Facebook, YouTube, or TikTok) and to the servers
that serve the video file. Those sites see your IP address and the request in
the same way a browser would. Their own privacy policies apply.

The app also offers an optional downloader update, which contacts GitHub to
fetch the latest yt-dlp engine. That is the only other request, and it happens
only when you tap the update button.

There is no proxy, no relay, and no Save & Send backend. The developer never
receives your links, files, cookies, or usage data.

## Cookies

Pasting cookies is optional. They are sent only to the site they belong to,
only during a download, and are never transmitted anywhere else. They are
encrypted at rest with an AES-GCM key held by the Android Keystore. During a
request, a temporary plaintext copy exists in the app cache and is deleted as
soon as the request finishes.

You can remove cookies at any time from Settings → **Login cookies**.

## Permissions

| Permission | Purpose |
| --- | --- |
| `INTERNET` | Fetch the page and the video |
| `ACCESS_NETWORK_STATE` | Answer whether the phone is on Wi-Fi, for the Wi-Fi-only setting |
| `WRITE_EXTERNAL_STORAGE` (Android 7–9 only) | Save to the Gallery on older Android versions |

The app does not request location, contacts, camera, microphone, notifications,
or background execution. It does not read your clipboard unless you tap
**Paste**.

## Children

The app is a personal tool and is not directed at children. It does not collect
personal information from anyone.

## Your choices

- Use the app without pasting cookies.
- Clear the cache and the Recent list at any time.
- Uninstall to remove every piece of app-private data.
- Download only content you have the right to save.

## Changes

This policy is versioned with the repository. A change is published in the same
commit as the app change that requires it, and the date above changes with it.

## Contact

Open an issue at
<https://github.com/AdilSiddiquiHQ/save-and-send/issues> for a privacy
question. Do not post cookies, private links, or other personal data in an
issue.
