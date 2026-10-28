#!/usr/bin/env python3
"""Checks that every translation key exists, is generated, and is used.

Run after editing an ARB file and before committing:

    python3 tool/check_l10n.py

It fails when:

* another language is missing a key that English has, or has a key English
  does not;
* `flutter gen-l10n` was not re-run, so the generated Dart is stale;
* a key is never referenced from `lib/src`, which means it was added to the
  ARBs but never reached the screen.
"""

from __future__ import annotations

import json
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
ARB_DIR = ROOT / "lib" / "l10n"
SRC_DIR = ROOT / "lib" / "src"
GENERATED = SRC_DIR / "l10n"

LANGUAGES = ["en", "ur", "hi", "ar", "bn"]


def load_keys(path: Path) -> set[str]:
    data = json.loads(path.read_text(encoding="utf-8"))
    return {
        key
        for key in data
        if not key.startswith("@") and not key.startswith("@@")
    }


def main() -> int:
    problems: list[str] = []

    english = load_keys(ARB_DIR / "app_en.arb")
    if not english:
        problems.append("lib/l10n/app_en.arb has no keys")

    for language in LANGUAGES:
        path = ARB_DIR / f"app_{language}.arb"
        if not path.exists():
            problems.append(f"missing {path.relative_to(ROOT)}")
            continue
        keys = load_keys(path)
        for key in sorted(english - keys):
            problems.append(f"{language}: missing key {key}")
        for key in sorted(keys - english):
            problems.append(f"{language}: key {key} is not in English")

    # The generated files are committed, so a stale copy ships stale strings.
    base = (GENERATED / "app_localizations.dart").read_text(encoding="utf-8")
    for key in sorted(english):
        if not re.search(rf"\bString (get )?{re.escape(key)}\b", base):
            problems.append(
                f"generated app_localizations.dart has no getter for {key} "
                "(run `flutter gen-l10n`)"
            )

    for language in LANGUAGES:
        path = GENERATED / f"app_localizations_{language}.dart"
        if not path.exists():
            problems.append(f"missing generated {path.relative_to(ROOT)}")
            continue
        body = path.read_text(encoding="utf-8")
        for key in sorted(english):
            if not re.search(rf"\bString (get )?{re.escape(key)}\b", body):
                problems.append(
                    f"generated {path.name} has no getter for {key} "
                    "(run `flutter gen-l10n`)"
                )

    source = "\n".join(
        path.read_text(encoding="utf-8")
        for path in sorted(SRC_DIR.rglob("*.dart"))
        if "l10n" not in path.parts
    )
    for key in sorted(english):
        # Keys are used both as `strings.cancel` and bare inside the
        # AppLocalizations extension helpers in i18n.dart.
        if not re.search(rf"\b{re.escape(key)}\b", source):
            problems.append(
                f"{key} is never used in lib/src, so it never reaches the APK"
            )

    if problems:
        print("l10n check failed:\n", file=sys.stderr)
        for problem in problems:
            print(f"  - {problem}", file=sys.stderr)
        return 1

    print(f"l10n ok: {len(english)} keys x {len(LANGUAGES)} languages")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
