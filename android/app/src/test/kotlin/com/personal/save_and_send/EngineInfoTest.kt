package com.personal.save_and_send

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test
import java.io.File
import java.util.zip.ZipFile

/**
 * Guards the hand-maintained version strings around the bundled yt-dlp.
 *
 * Three places have to agree: the zipapp in `res/raw/ytdlp`, [EngineInfo], and
 * `tool/ytdlp-version.txt`. A mismatch used to be invisible until a user
 * opened Settings and saw the wrong date.
 */
class EngineInfoTest {

    private fun zipapp(): File {
        val candidates = listOf(
            File("src/main/res/raw/ytdlp"),
            File("app/src/main/res/raw/ytdlp"),
        )
        return candidates.firstOrNull { it.isFile }
            ?: error("res/raw/ytdlp not found from ${File(".").absolutePath}")
    }

    private fun zipappVersion(): String {
        ZipFile(zipapp()).use { zip ->
            val entry = zip.getEntry("yt_dlp/version.py")
                ?: error("yt_dlp/version.py is missing from the zipapp")
            val text = zip.getInputStream(entry).bufferedReader().readText()
            val match = Regex("""__version__\s*=\s*'([^']+)'""").find(text)
            return match?.groupValues?.get(1)
                ?: error("no __version__ in yt_dlp/version.py")
        }
    }

    @Test
    fun `the bundled zipapp is the declared version`() {
        assertEquals(EngineInfo.YTDLP_VERSION, zipappVersion())
    }

    @Test
    fun `the tool version file is the declared version`() {
        val candidates = listOf(
            File("../../tool/ytdlp-version.txt"),
            File("../tool/ytdlp-version.txt"),
        )
        val file = candidates.firstOrNull { it.isFile }
            ?: error("tool/ytdlp-version.txt not found")
        assertEquals(EngineInfo.YTDLP_VERSION, file.readText().trim())
    }

    @Test
    fun `the zipapp is executable python`() {
        val head = zipapp().inputStream().use { stream ->
            ByteArray(24).also { stream.read(it) }.toString(Charsets.UTF_8)
        }
        assertTrue(head.startsWith("#!/usr/bin/env python3"))
    }
}
