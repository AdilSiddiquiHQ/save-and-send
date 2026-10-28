#!/usr/bin/env bash
# Builds, verifies, checksums, tags, and publishes one release.
#
#   tool/release.sh                 # full release
#   tool/release.sh --no-push       # build and produce artifacts only
#   tool/release.sh --skip-tests    # skip analyze/unit/widget tests
#
# Run it from a clean main branch after the version and RELEASE_NOTES file are
# committed. See docs/RELEASING.md for the full checklist.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

BUDGET_MB="${BUDGET_MB:-68}"
PUSH=1
TESTS=1
for arg in "$@"; do
  case "$arg" in
    --no-push) PUSH=0 ;;
    --skip-tests) TESTS=0 ;;
    -h|--help)
      sed -n '2,9p' "$0" | sed 's/^# \{0,1\}//'
      exit 0
      ;;
    *)
      echo "Unknown option: $arg" >&2
      exit 2
      ;;
  esac
done

say() { printf '\n\033[1m==> %s\033[0m\n' "$*"; }
fail() { printf '\033[31merror:\033[0m %s\n' "$*" >&2; exit 1; }

# ---------------------------------------------------------------------------
# Version and preconditions
# ---------------------------------------------------------------------------

VERSION="$(sed -n 's/^version: \([0-9.]*\)+.*/\1/p' pubspec.yaml)"
BUILD="$(sed -n 's/^version: [0-9.]*+\([0-9]*\)$/\1/p' pubspec.yaml)"
[ -n "$VERSION" ] || fail "could not read version from pubspec.yaml"

DECLARED="$(sed -n "s/^const String kAppVersion = '\(.*\)';/\1/p" lib/src/version.dart)"
[ "$DECLARED" = "$VERSION" ] ||
  fail "lib/src/version.dart says $DECLARED but pubspec.yaml says $VERSION"

NOTES="docs/RELEASE_NOTES_v${VERSION}.md"
[ -f "$NOTES" ] || fail "missing $NOTES"

git rev-parse --is-inside-work-tree >/dev/null 2>&1 || fail "not a git repository"
BRANCH="$(git rev-parse --abbrev-ref HEAD)"
[ "$BRANCH" = "main" ] || fail "release from main, not $BRANCH"
[ -z "$(git status --porcelain)" ] || fail "working tree is not clean; commit first"
if git rev-parse -q --verify "refs/tags/v$VERSION" >/dev/null; then
  fail "tag v$VERSION already exists"
fi

command -v flutter >/dev/null || fail "flutter is not on PATH"
command -v gh >/dev/null || fail "gh is not on PATH"
if [ "$PUSH" = 1 ]; then
  gh auth status >/dev/null 2>&1 || fail "run gh auth login first"
  git fetch --quiet origin main
  [ "$(git rev-parse HEAD)" = "$(git rev-parse origin/main)" ] ||
    fail "main differs from origin/main; push or pull first"
fi

say "Releasing Save & Send $VERSION ($BUILD)"

# ---------------------------------------------------------------------------
# Checks
# ---------------------------------------------------------------------------

if [ "$TESTS" = 1 ]; then
  say "Static checks and tests"
  flutter analyze
  python3 tool/check_l10n.py
  flutter test
  (cd android && ./gradlew :app:testDebugUnitTest --console=plain)
fi

# ---------------------------------------------------------------------------
# Build
# ---------------------------------------------------------------------------

say "Building the release APK"
flutter pub get
flutter build apk --release --target-platform android-arm64

RAW="build/app/outputs/flutter-apk/app-release.apk"
[ -f "$RAW" ] || fail "the build produced no APK"

mkdir -p dist
APK="dist/SaveAndSend-v${VERSION}-arm64.apk"
cp "$RAW" "$APK"

BYTES="$(wc -c <"$APK" | tr -d ' ')"
MIB=$((BYTES / 1024 / 1024))
[ "$BYTES" -le $((BUDGET_MB * 1024 * 1024)) ] ||
  fail "APK is ${MIB} MiB, over the ${BUDGET_MB} MiB budget"

say "Checking the APK"
# One ABI only, and no accidental debug or test payloads.
ABIS="$(unzip -l "$APK" | grep -o 'lib/[^/]*/' | sort -u)"
[ "$ABIS" = "lib/arm64-v8a/" ] ||
  fail "expected only lib/arm64-v8a/, found: ${ABIS:-no native libraries}"

SDK_TOOLS="${ANDROID_HOME:-$HOME/Library/Android/sdk}/build-tools"
APKSIGNER="$(find "$SDK_TOOLS" -name apksigner -type f 2>/dev/null | sort -V | tail -1 || true)"
CERT=""
if [ -n "$APKSIGNER" ]; then
  CERT="$("$APKSIGNER" verify --print-certs "$APK" |
    sed -n 's/^Signer #1 certificate SHA-256 digest: //p')"
  [ -n "$CERT" ] || fail "APK is not signed"
  if ! "$APKSIGNER" verify "$APK" >/dev/null 2>&1; then
    fail "APK signature verification failed"
  fi
  echo "signing certificate: $CERT"
else
  echo "warning: apksigner not found; skipping signature verification" >&2
fi

# ---------------------------------------------------------------------------
# Checksums, SBOM, notes
# ---------------------------------------------------------------------------

say "Writing checksums and SBOM"
if command -v sha256sum >/dev/null; then
  SHA="$(sha256sum "$APK" | cut -d' ' -f1)"
else
  SHA="$(shasum -a 256 "$APK" | cut -d' ' -f1)"
fi
echo "$SHA  SaveAndSend-v${VERSION}-arm64.apk" >"dist/SHA256SUMS-${VERSION}.txt"

# Keep the rolling file in release order and free of duplicates.
{
  grep -v "SaveAndSend-v${VERSION}-arm64.apk" dist/SHA256SUMS.txt 2>/dev/null || true
  echo "$SHA  SaveAndSend-v${VERSION}-arm64.apk"
} | sort -V -k2 >"dist/SHA256SUMS.txt.tmp"
mv "dist/SHA256SUMS.txt.tmp" dist/SHA256SUMS.txt

python3 tool/sbom.py --output "dist/sbom-${VERSION}.cdx.json"

BODY="dist/RELEASE_NOTES_v${VERSION}.md"
{
  cat "$NOTES"
  printf '\n## Release integrity\n\n| | |\n| --- | --- |\n'
  printf '| APK | `SaveAndSend-v%s-arm64.apk` |\n' "$VERSION"
  printf '| Size | %s MiB |\n' "$MIB"
  printf '| SHA-256 | `%s` |\n' "$SHA"
  if [ -n "$CERT" ]; then
    printf '| Signing certificate SHA-256 | `%s` |\n' "$CERT"
  fi
  printf '| Version | %s (%s) |\n' "$VERSION" "$BUILD"
  printf '| Min SDK | 24 |\n| ABI | `arm64-v8a` |\n'
} >"$BODY"

say "Artifacts"
printf '  %s (%s MiB)\n  %s\n  %s\n  %s\n' "$APK" "$MIB" \
  "dist/SHA256SUMS-${VERSION}.txt" "dist/sbom-${VERSION}.cdx.json" "$BODY"
echo "  sha256 $SHA"

# ---------------------------------------------------------------------------
# Tag and publish
# ---------------------------------------------------------------------------

say "Tagging v$VERSION"
git tag -a "v$VERSION" -m "Save & Send $VERSION"

if [ "$PUSH" = 0 ]; then
  cat <<EOF

Dry run: the tag exists locally and nothing was pushed.
Publish with:

  git push origin main
  git push origin v$VERSION
  gh release create v$VERSION "$APK" "dist/SHA256SUMS-${VERSION}.txt" "dist/sbom-${VERSION}.cdx.json" \\
    --title "Save & Send $VERSION" --notes-file "$BODY"
EOF
  exit 0
fi

git push origin main
git push origin "v$VERSION"

say "Creating the GitHub release"
gh release create "v$VERSION" \
  "$APK" "dist/SHA256SUMS-${VERSION}.txt" "dist/sbom-${VERSION}.cdx.json" \
  --title "Save & Send $VERSION" \
  --notes-file "$BODY"

say "Done"
gh release view "v$VERSION" --json url -q .url
