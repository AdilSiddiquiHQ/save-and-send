#!/usr/bin/env python3
"""Writes a CycloneDX SBOM for one release.

    python3 tool/sbom.py                    # dist/sbom-<version>.cdx.json
    python3 tool/sbom.py --output /tmp/x.json

The package list comes from `pubspec.lock` (pub) and Gradle's
`releaseRuntimeClasspath` (Maven), plus the engines that are shipped inside the
APK but pulled in at runtime: youtubedl-android, yt-dlp, Python, and FFmpeg.

It only uses the standard library so it runs on a fresh clone.
"""

from __future__ import annotations

import argparse
import datetime as dt
import json
import re
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
APP_NAME = "save-and-send"
APP_SLUG = "save-and-send"


def app_version() -> str:
    for line in (ROOT / "pubspec.yaml").read_text(encoding="utf-8").splitlines():
        if line.startswith("version:"):
            return line.split(":", 1)[1].strip().split("+")[0]
    raise SystemExit("pubspec.yaml has no version")


def pub_components() -> list[dict]:
    lock = (ROOT / "pubspec.lock").read_text(encoding="utf-8")
    components = []
    # The lock file is YAML, but every package block has this fixed shape:
    #   name:
    #     dependency: "..."
    #     description: ...
    #     source: hosted
    #     version: "1.2.3"
    for match in re.finditer(
        r"^  ([a-z0-9_]+):\n(?:    .*\n)*?    version: \"([^\"]+)\"",
        lock,
        re.MULTILINE,
    ):
        name, version = match.group(1), match.group(2)
        components.append(
            {
                "type": "library",
                "name": name,
                "version": version,
                "purl": f"pkg:pub/{name}@{version}",
                "scope": "required",
            }
        )
    return components


def gradle_components() -> list[dict]:
    try:
        output = subprocess.run(
            [
                "./gradlew",
                "-q",
                ":app:dependencies",
                "--configuration",
                "releaseRuntimeClasspath",
            ],
            cwd=ROOT / "android",
            check=True,
            capture_output=True,
            text=True,
            timeout=600,
        ).stdout
    except (subprocess.SubprocessError, OSError) as error:
        print(f"warning: Gradle dependency tree unavailable: {error}", file=sys.stderr)
        return []

    seen: set[tuple[str, str, str]] = set()
    components = []
    # Lines look like: +--- com.example:lib:1.2.3 (*)
    for match in re.finditer(
        r"[+\\|]--- ([\w.\-]+):([\w.\-]+):([\w.\-+]+)",
        output,
    ):
        group, artifact, version = match.groups()
        key = (group, artifact, version)
        if key in seen:
            continue
        seen.add(key)
        components.append(
            {
                "type": "library",
                "group": group,
                "name": artifact,
                "version": version,
                "purl": f"pkg:maven/{group}/{artifact}@{version}",
                "scope": "required",
            }
        )
    return components


def engine_components() -> list[dict]:
    ytdlp = (ROOT / "tool" / "ytdlp-version.txt").read_text(encoding="utf-8").strip()
    return [
        {
            "type": "library",
            "name": "youtubedl-android",
            "version": "0.18.1",
            "purl": "pkg:maven/io.github.junkfood02.youtubedl-android/library@0.18.1",
            "scope": "required",
            "licenses": [{"license": {"id": "GPL-3.0-only"}}],
        },
        {
            "type": "application",
            "name": "yt-dlp",
            "version": ytdlp,
            "purl": f"pkg:github/yt-dlp/yt-dlp@{ytdlp}",
            "scope": "required",
            "licenses": [{"license": {"id": "Unlicense"}}],
        },
        {
            "type": "application",
            "name": "FFmpeg",
            "version": "bundled with youtubedl-android 0.18.1",
            "scope": "required",
            "licenses": [{"license": {"id": "GPL-3.0-only"}}],
        },
    ]


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", type=Path)
    args = parser.parse_args()

    version = app_version()
    output = args.output or ROOT / "dist" / f"sbom-{version}.cdx.json"
    output.parent.mkdir(parents=True, exist_ok=True)

    components = pub_components() + gradle_components() + engine_components()
    components.sort(key=lambda item: (item["name"], item["version"]))

    bom = {
        "bomFormat": "CycloneDX",
        "specVersion": "1.5",
        "version": 1,
        "metadata": {
            "timestamp": dt.datetime.now(dt.timezone.utc).strftime(
                "%Y-%m-%dT%H:%M:%SZ"
            ),
            "tools": [{"name": "save-and-send/tool/sbom.py"}],
            "component": {
                "type": "application",
                "name": APP_NAME,
                "version": version,
                "purl": f"pkg:github/AdilSiddiquiHQ/{APP_SLUG}@{version}",
            },
        },
        "components": components,
    }

    output.write_text(json.dumps(bom, indent=2) + "\n", encoding="utf-8")
    shown = output.relative_to(ROOT) if output.is_relative_to(ROOT) else output
    print(f"wrote {shown} with {len(components)} components")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
