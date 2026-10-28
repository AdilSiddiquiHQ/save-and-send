package com.personal.save_and_send

import java.io.File
import java.util.Locale

/**
 * Pure decisions behind the Status tools: how many parts a clip needs, what
 * bitrate a target size allows, which FFmpeg arguments to use, and which old
 * temporary folders can go.
 *
 * Nothing here touches Android or runs a process, so all of it is covered by
 * plain JVM tests.
 */
object TransformPlanner {

    /** WhatsApp Status limit with a small safety margin. */
    const val PART_MS = 59_500L

    /** Old Status outputs are kept for re-sharing until this much is on disk. */
    const val CACHE_BYTES = 250L * 1024 * 1024

    const val MIN_VIDEO_KBPS = 220
    const val MAX_VIDEO_KBPS = 6000

    /** Blurred 9:16 canvas with the untouched picture centred on top. */
    fun fitFilter(): String =
        "[0:v]split=2[bgs][fgs];" +
            "[bgs]scale=270:480:force_original_aspect_ratio=increase," +
            "crop=270:480,boxblur=8:2,scale=1080:1920[bg];" +
            "[fgs]scale=1080:1920:force_original_aspect_ratio=decrease," +
            "scale=trunc(iw/2)*2:trunc(ih/2)*2[fg];" +
            "[bg][fg]overlay=(W-w)/2:(H-h)/2,format=yuv420p[v]"

    fun splitCount(durationMs: Long): Int {
        if (durationMs <= 0L) return 1
        return ((durationMs + PART_MS - 1) / PART_MS).toInt().coerceAtLeast(1)
    }

    /**
     * Video bitrate that fits [targetBytes] for [durationMs], after reserving
     * room for a 96 kbps audio track. Clamped so a tiny target still produces a
     * watchable picture.
     */
    fun compressedVideoKbps(
        targetBytes: Long,
        durationMs: Long,
        hasAudio: Boolean,
    ): Int {
        if (targetBytes <= 0L || durationMs <= 0L) return MIN_VIDEO_KBPS
        val seconds = durationMs / 1000.0
        val totalKbps = (targetBytes * 8.0 / seconds / 1000.0).toInt()
        val audioKbps = if (hasAudio) 96 else 0
        return (totalKbps - audioKbps).coerceIn(MIN_VIDEO_KBPS, MAX_VIDEO_KBPS)
    }

    /**
     * The full FFmpeg command for one H.264/AAC output. Keeping this pure means
     * a test can check ordering (fast seek before the input, `+faststart` last)
     * without a phone.
     */
    fun encodeCommand(
        ffmpegPath: String,
        inputPath: String,
        outputPath: String,
        hasAudio: Boolean,
        startMs: Long? = null,
        durationMs: Long? = null,
        filter: String? = null,
        videoKbps: Int? = null,
    ): List<String> {
        val command = mutableListOf(
            ffmpegPath,
            "-y",
            "-nostdin",
            "-hide_banner",
            "-loglevel", "error",
            "-progress", "pipe:1",
            "-nostats",
        )
        if (startMs != null && startMs > 0L) {
            command += listOf("-ss", seconds(startMs))
        }
        command += listOf("-i", inputPath)
        if (durationMs != null) {
            command += listOf("-t", seconds(durationMs))
        }
        if (filter != null) {
            command += listOf(
                "-filter_complex", filter,
                "-map", "[v]",
                "-map", "0:a:0?",
            )
        } else {
            command += listOf("-map", "0:v:0", "-map", "0:a:0?")
        }

        if (videoKbps == null) {
            command += listOf(
                "-c:v", "libx264",
                "-preset", "veryfast",
                "-crf", "23",
                "-pix_fmt", "yuv420p",
            )
        } else {
            command += listOf(
                "-c:v", "libx264",
                "-preset", "veryfast",
                "-b:v", "${videoKbps}k",
                "-maxrate", "${videoKbps * 11 / 10}k",
                "-bufsize", "${videoKbps * 2}k",
                "-pix_fmt", "yuv420p",
            )
        }
        if (hasAudio) {
            command += listOf(
                "-c:a", "aac",
                "-b:a", if (videoKbps == null) "128k" else "96k",
                "-ac", "2",
            )
        }
        command += listOf("-movflags", "+faststart", outputPath)
        return command
    }

    /**
     * Old transform folders to delete so the cache stays under [maxBytes].
     * Never returns a folder named in [keepNames]; oldest folders go first.
     */
    fun staleDirs(
        dirs: List<File>,
        keepNames: Set<String>,
        maxBytes: Long = CACHE_BYTES,
    ): List<File> {
        val folders = dirs.filter { it.isDirectory }
        var total = folders.sumOf { sizeOf(it) }
        if (total <= maxBytes) return emptyList()

        val doomed = mutableListOf<File>()
        val candidates = folders
            .filter { it.name !in keepNames }
            .sortedBy { it.lastModified() }
        for (dir in candidates) {
            if (total <= maxBytes) break
            doomed += dir
            total -= sizeOf(dir)
        }
        return doomed
    }

    private fun sizeOf(dir: File): Long =
        dir.walkTopDown().filter { it.isFile }.sumOf { it.length() }

    private fun seconds(ms: Long): String =
        String.format(Locale.US, "%.3f", ms / 1000.0)
}
