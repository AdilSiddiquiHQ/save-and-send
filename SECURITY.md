# Security policy

## Supported versions

| Version | Supported |
| --- | --- |
| 1.x | Yes |

This is a personal, sideloaded Android app. Security fixes are applied to the
latest release.

## Reporting a vulnerability

Please do **not** open a public issue for a security problem. Use the
repository's **Security → Report a vulnerability** flow
(GitHub Security Advisories) so the report stays private.

Include:

- the app version and Android version;
- a description of the issue and its impact;
- steps to reproduce;
- any relevant logs with secrets removed.

Never include cookies, session tokens, keystore passwords, or personal media in
a report. If a report involves a third-party component (yt-dlp, FFmpeg,
youtubedl-android), it may be forwarded upstream.

## Scope

In scope:

- the Dart and Kotlin code in this repository;
- the Android manifest, FileProvider configuration, and intent handling;
- the local cookie store and release signing configuration.

Out of scope:

- vulnerabilities in Instagram, Facebook, YouTube, TikTok, WhatsApp, or Android
  itself;
- content downloaded with the app;
- builds signed with a key you do not control.

## Secrets

The repository must never contain:

- `android/key.properties`;
- `*.jks` or `*.keystore` files;
- `cookies.txt` or exported browser sessions;
- personal access tokens or CI secrets.

These paths are covered by `.gitignore`. If a secret is committed by mistake,
revoke it first, then rewrite the history before publishing.
