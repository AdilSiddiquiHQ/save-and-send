package com.personal.save_and_send

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test
import java.io.File
import java.nio.file.Files

/**
 * Plain JVM tests for the Status planning logic. No phone, no FFmpeg process.
 */
class TransformPlannerTest {

    // --- split ------------------------------------------------------------

    @Test
    fun `a clip at the limit stays one part`() {
        assertEquals(1, TransformPlanner.splitCount(TransformPlanner.PART_MS))
    }

    @Test
    fun `one millisecond over the limit becomes two parts`() {
        assertEquals(2, TransformPlanner.splitCount(TransformPlanner.PART_MS + 1))
    }

    @Test
    fun `parts round up`() {
        assertEquals(3, TransformPlanner.splitCount(TransformPlanner.PART_MS * 2 + 1))
        assertEquals(1, TransformPlanner.splitCount(1))
    }

    @Test
    fun `an empty duration still asks for one part`() {
        assertEquals(1, TransformPlanner.splitCount(0))
        assertEquals(1, TransformPlanner.splitCount(-500))
    }

    // --- compress ---------------------------------------------------------

    @Test
    fun `bitrate leaves room for audio`() {
        // 8 MiB over 60 s is about 1118 kbps; minus 96 for audio.
        val kbps = TransformPlanner.compressedVideoKbps(
            targetBytes = 8L * 1024 * 1024,
            durationMs = 60_000,
            hasAudio = true,
        )
        assertEquals(1022, kbps)
    }

    @Test
    fun `bitrate is higher when there is no audio track`() {
        val withAudio = TransformPlanner.compressedVideoKbps(8L * 1024 * 1024, 60_000, true)
        val silent = TransformPlanner.compressedVideoKbps(8L * 1024 * 1024, 60_000, false)
        assertEquals(96, silent - withAudio)
    }

    @Test
    fun `a tiny target is clamped to a watchable bitrate`() {
        assertEquals(
            TransformPlanner.MIN_VIDEO_KBPS,
            TransformPlanner.compressedVideoKbps(200_000, 600_000, true),
        )
    }

    @Test
    fun `a huge target is clamped instead of wasting space`() {
        assertEquals(
            TransformPlanner.MAX_VIDEO_KBPS,
            TransformPlanner.compressedVideoKbps(900L * 1024 * 1024, 5_000, true),
        )
    }

    // --- fit --------------------------------------------------------------

    @Test
    fun `fit pads without cropping and keeps dimensions even`() {
        val filter = TransformPlanner.fitFilter()
        assertTrue(filter.contains("boxblur"))
        assertTrue(filter.contains("scale=trunc(iw/2)*2:trunc(ih/2)*2"))
        assertTrue(filter.contains("overlay=(W-w)/2:(H-h)/2"))
        assertTrue(filter.contains("scale=1080:1920"))
    }

    // --- command ----------------------------------------------------------

    private fun command(
        hasAudio: Boolean = true,
        startMs: Long? = null,
        durationMs: Long? = null,
        filter: String? = null,
        videoKbps: Int? = null,
    ) = TransformPlanner.encodeCommand(
        ffmpegPath = "/data/libffmpeg.so",
        inputPath = "/tmp/in.mp4",
        outputPath = "/tmp/out.mp4",
        hasAudio = hasAudio,
        startMs = startMs,
        durationMs = durationMs,
        filter = filter,
        videoKbps = videoKbps,
    )

    @Test
    fun `faststart is last and progress is on stdout`() {
        val args = command()
        val last = args.takeLast(3)
        assertEquals(listOf("-movflags", "+faststart", "/tmp/out.mp4"), last)
        assertTrue(args.windowed(2).contains(listOf("-progress", "pipe:1")))
    }

    @Test
    fun `fast seek comes before the input`() {
        val args = command(startMs = 1500)
        assertTrue(args.indexOf("-ss") < args.indexOf("-i"))
        assertEquals("1.500", args[args.indexOf("-ss") + 1])
    }

    @Test
    fun `no duration means no trim flag`() {
        val args = command(durationMs = null)
        assertFalse(args.contains("-t"))
    }

    @Test
    fun `duration is written in seconds`() {
        val args = command(durationMs = 59_500)
        assertEquals("59.500", args[args.indexOf("-t") + 1])
    }

    @Test
    fun `a filter maps the labelled video stream`() {
        val args = command(filter = "[v]")
        assertEquals("[v]", args[args.indexOf("-filter_complex") + 1])
        assertTrue(args.windowed(2).contains(listOf("-map", "[v]")))
        assertTrue(args.windowed(2).contains(listOf("-map", "0:a:0?")))
    }

    @Test
    fun `no filter maps the first video stream`() {
        val args = command(filter = null)
        assertTrue(args.windowed(2).contains(listOf("-map", "0:v:0")))
    }

    @Test
    fun `a target bitrate also sets maxrate and bufsize`() {
        val args = command(videoKbps = 1000)
        assertEquals("1000k", args[args.indexOf("-b:v") + 1])
        assertEquals("1100k", args[args.indexOf("-maxrate") + 1])
        assertEquals("2000k", args[args.indexOf("-bufsize") + 1])
        assertEquals("96k", args[args.indexOf("-b:a") + 1])
    }

    @Test
    fun `crf is used when there is no target size`() {
        val args = command(videoKbps = null)
        assertTrue(args.windowed(2).contains(listOf("-crf", "23")))
        assertFalse(args.contains("-b:v"))
        assertEquals("128k", args[args.indexOf("-b:a") + 1])
    }

    @Test
    fun `a silent source gets no audio encoder`() {
        assertFalse(command(hasAudio = false).contains("-c:a"))
    }

    // --- cache ------------------------------------------------------------

    private fun tempFolder(name: String, ageMs: Long, bytes: Int): File {
        val dir = Files.createTempDirectory(name).toFile()
        File(dir, "out.mp4").writeBytes(ByteArray(bytes))
        dir.setLastModified(System.currentTimeMillis() - ageMs)
        return dir
    }

    @Test
    fun `a cache under the cap keeps everything`() {
        val dirs = listOf(tempFolder("a", 5_000, 10), tempFolder("b", 1_000, 10))
        assertTrue(TransformPlanner.staleDirs(dirs, keepNames = setOf("a"), maxBytes = 1_000).isEmpty())
    }

    @Test
    fun `old folders go first`() {
        val old = tempFolder("old", 120_000, 600)
        val recent = tempFolder("recent", 1_000, 600)
        val doomed = TransformPlanner.staleDirs(
            listOf(old, recent),
            keepNames = emptySet(),
            maxBytes = 800,
        )
        assertEquals(listOf(old), doomed)
    }

    @Test
    fun `the current request folder is never removed`() {
        val old = tempFolder("old", 120_000, 600)
        val current = tempFolder("current", 1_000, 600)
        val doomed = TransformPlanner.staleDirs(
            listOf(old, current),
            keepNames = setOf(current.name),
            maxBytes = 700,
        )
        assertEquals(listOf(old), doomed)
    }

    @Test
    fun `the folder that holds the input is never removed`() {
        // Regression: applying a second Status tool to a part used to delete
        // the part's own folder, taking the input with it.
        val source = tempFolder("source", 600_000, 600)
        val other = tempFolder("other", 500_000, 600)
        val doomed = TransformPlanner.staleDirs(
            listOf(source, other),
            keepNames = setOf(source.name),
            maxBytes = 100,
        )
        assertEquals(listOf(other), doomed)
        assertFalse(doomed.contains(source))
    }

    @Test
    fun `pruning brings the total under the cap`() {
        val dirs = (1..5).map { tempFolder("d$it", it * 10_000L, 300) }
        val doomed = TransformPlanner.staleDirs(dirs, keepNames = emptySet(), maxBytes = 700)
        val remaining = dirs - doomed.toSet()
        val left = remaining.sumOf { it.walkTopDown().filter { f -> f.isFile }.sumOf { f -> f.length() } }
        assertTrue(left <= 700)
        assertTrue(doomed.isNotEmpty())
    }
}
