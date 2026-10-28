package com.personal.save_and_send

/**
 * The yt-dlp build that ships inside the APK at `res/raw/ytdlp`.
 *
 * Keep this in step with `tool/ytdlp-version.txt`, the README badge, and
 * `THIRD_PARTY_NOTICES.md`. `EngineInfoTest` reads the zipapp itself, so a
 * version string that no longer matches the asset fails the build.
 */
object EngineInfo {
    const val YTDLP_VERSION = "2026.10.26"
}
