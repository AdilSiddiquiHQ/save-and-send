# Releasing

One script does the whole release: version checks, tests, the arm64 build, the
size and ABI checks, checksums, the SBOM, the git tag, and the GitHub release.

```bash
tool/release.sh
```

It refuses to run unless the working tree is clean, you are on `main`, `main`
matches `origin/main`, the tag does not exist yet, and
`docs/RELEASE_NOTES_v<version>.md` exists.

## Before you run it

1. **Pick the version.** Patch for fixes, minor for a feature.

   ```text
   pubspec.yaml            version: 1.3.1+7
   lib/src/version.dart    const String kAppVersion = '1.3.1';
   ```

   The `+N` is the Android `versionCode` and must always go up. Android
   refuses an install with a lower code.

2. **Write the notes.** Copy the previous file:

   ```bash
   cp docs/RELEASE_NOTES_v1.3.0.md docs/RELEASE_NOTES_v1.3.1.md
   ```

   Describe what changed for a user, not the commit log. The script appends the
   release-integrity table (size, SHA-256, signing certificate) itself, so do
   not fill it in by hand.

3. **Update [CHANGELOG.md](../CHANGELOG.md)** with a new `## [1.3.1]` section.

4. **Refresh the screenshots and goldens** if the UI changed:

   ```bash
   flutter test --update-goldens test/visual_test.dart
   ```

5. **Commit everything**, then push `main`:

   ```bash
   git add -A
   git commit -m "Release 1.3.1"
   git push origin main
   ```

## What the script does

| Step | Detail |
| --- | --- |
| Version check | `pubspec.yaml`, `lib/src/version.dart`, the notes file, and the tag must agree |
| Tests | `flutter analyze`, `tool/check_l10n.py`, `flutter test`, `:app:testDebugUnitTest` |
| Build | `flutter build apk --release --target-platform android-arm64` |
| Size budget | Fails above `BUDGET_MB` (default 68 MiB); override with `BUDGET_MB=70 tool/release.sh` |
| ABI check | The APK must contain only `lib/arm64-v8a/` |
| Signature | `apksigner verify` must pass, and the certificate digest is recorded |
| Checksums | `dist/SHA256SUMS-<version>.txt` and the rolling `dist/SHA256SUMS.txt` |
| SBOM | `dist/sbom-<version>.cdx.json` from `pubspec.lock` and Gradle's runtime classpath |
| Notes | `docs/RELEASE_NOTES_v<version>.md` plus a generated integrity table |
| Publish | `git tag`, `git push`, `gh release create` with APK, checksum, and SBOM |

Useful flags:

```bash
tool/release.sh --skip-tests    # you just ran the suite
tool/release.sh --no-push       # build and tag locally, print the publish commands
```

`--no-push` is the safe first attempt: it produces every artifact and the tag
without touching GitHub. Delete the tag with `git tag -d v1.3.1` if you need to
redo the build.

## Signing

The release is signed with the key named in `android/key.properties`:

```properties
storeFile=/Users/you/.config/save-and-send/save-and-send-release.jks
storePassword=...
keyAlias=save-and-send
keyPassword=...
```

Without that file, Gradle falls back to the debug key. The build still works,
but you **cannot** publish it: an APK signed with a different key cannot update
an installed copy, and the fingerprint in the notes would change.

Back up the keystore and its password somewhere you control. Losing them means
every existing install must be uninstalled before it can be updated.

## After the release

- Check the [CI run](https://github.com/AdilSiddiquiHQ/save-and-send/actions)
  on the tagged commit.
- Open the release page and confirm the APK, checksum, and SBOM are attached.
- Download the APK once and verify it:

  ```bash
  shasum -a 256 SaveAndSend-v1.3.1-arm64.apk
  diff <(shasum -a 256 SaveAndSend-v1.3.1-arm64.apk) \
       dist/SHA256SUMS-1.3.1.txt
  ```

- Install over the previous version on a phone and run one download, one
  Status action, and one share.

## If something goes wrong

| Symptom | Fix |
| --- | --- |
| `working tree is not clean` | Commit or stash. The build must come from a tagged commit. |
| `main differs from origin/main` | `git pull --rebase` or push your commit. |
| `tag v1.3.1 already exists` | You already released it. Bump the version instead of reusing one. |
| `APK is N MiB, over the budget` | Check for a new dependency or an extra ABI. Raise `BUDGET_MB` only after deciding the growth is acceptable. |
| `APK is not signed` | `android/key.properties` is missing or points at the wrong keystore. |
| `expected only lib/arm64-v8a/` | A dependency gained another ABI. Keep the `--target-platform android-arm64` build and remove the dependency if needed. |

Never replace an APK attached to a published release. Bump the version and
publish a new one so the checksums stay meaningful.
