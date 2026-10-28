package com.personal.save_and_send

import android.content.Context
import android.media.MediaExtractor
import android.media.MediaFormat
import android.media.MediaMetadataRetriever
import com.yausername.youtubedl_android.YoutubeDL
import com.yausername.youtubedl_android.YoutubeDLRequest
import org.json.JSONObject
import java.io.File
import java.io.IOException
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicBoolean
import kotlin.math.max
import kotlin.math.roundToLong

/**
 * Downloads one link with the bundled yt-dlp + FFmpeg, then makes the file
 * safe to hand to WhatsApp: MP4 / H.264 / AAC, at most 60 seconds.
 */
class Downloader(
    private val context: Context,
    private val emit: (Map<String, Any?>) -> Unit,
    private val saveToGallery: (File, String, Boolean) -> Map<String, Any?>,
) {
    data class Options(
        val maxHeight: Int = 0,
        val audioOnly: Boolean = false,
        val alternate: Boolean = false,
    )

    data class ProbeOption(
        val height: Int,
        val sizeBytes: Long,
        val audio: Boolean,
    ) {
        fun toMap(): Map<String, Any?> = mapOf(
            "height" to height,
            "sizeBytes" to sizeBytes,
            "audio" to audio,
        )
    }

    data class Probe(
        val title: String,
        val durationMs: Long,
        val thumbnailUrl: String?,
        val options: List<ProbeOption>,
    )
    data class Result(
        val file: File,
        val title: String,
        val durationMs: Long,
        val width: Int,
        val height: Int,
        val hasAudio: Boolean,
        val thumbnail: File?,
        val thumbnailUrl: String?,
        val trimmed: Boolean,
        val uri: String?,
        val path: String?,
        val audioOnly: Boolean,
    )

    class DownloadException(
        val code: String,
        override val message: String,
        val detail: String? = null,
    ) : Exception(message)

    private data class Inspected(
        val durationMs: Long,
        val width: Int,
        val height: Int,
        val rotation: Int,
        val hasAudio: Boolean,
        val videoMime: String?,
        val audioMime: String?,
        val audioChannels: Int,
    ) {
        val displayWidth: Int
            get() = if (rotation == 90 || rotation == 270) height else width
        val displayHeight: Int
            get() = if (rotation == 90 || rotation == 270) width else height
    }

    @Volatile private var cancelled = false
    @Volatile private var activeId: String? = null
    @Volatile private var ffmpegProcess: Process? = null
    private val probeBusy = AtomicBoolean(false)

    fun isBusy(): Boolean = activeId != null || globalBusy.get()

    fun start(
        requestId: String,
        url: String,
        options: Options = Options(),
    ) {
        if (activeId != null || !globalBusy.compareAndSet(false, true)) {
            emit(
                mapOf(
                    "type" to "error",
                    "requestId" to requestId,
                    "code" to "busy",
                    "message" to "Another download is already running.",
                    "detail" to null,
                )
            )
            return
        }
        activeId = requestId
        cancelled = false

        Thread({
            try {
                // A size check and a download cannot share the Python runtime.
                // Let an in-flight probe finish instead of failing the tap.
                var waited = 0
                while (probeBusy.get() && !cancelled && waited < 15_000) {
                    Thread.sleep(100)
                    waited += 100
                }
                if (cancelled) throw YoutubeDL.CanceledException()
                val result = run(requestId, url, options)
                if (cancelled) throw YoutubeDL.CanceledException()
                emit(
                    mapOf(
                        "type" to "done",
                        "requestId" to requestId,
                        "path" to result.file.absolutePath,
                        "title" to result.title,
                        "durationMs" to result.durationMs,
                        "width" to result.width,
                        "height" to result.height,
                        "hasAudio" to result.hasAudio,
                        "thumbnailPath" to result.thumbnail?.absolutePath,
                        "thumbnailUrl" to result.thumbnailUrl,
                        "trimmed" to result.trimmed,
                        "sizeBytes" to result.file.length(),
                        "uri" to result.uri,
                        "savedPath" to result.path,
                        "kind" to if (result.audioOnly) "audio" else "video",
                    )
                )
            } catch (e: YoutubeDL.CanceledException) {
                emit(mapOf("type" to "cancelled", "requestId" to requestId))
            } catch (e: DownloadException) {
                if (cancelled) {
                    emit(mapOf("type" to "cancelled", "requestId" to requestId))
                } else {
                    emit(
                        mapOf(
                            "type" to "error",
                            "requestId" to requestId,
                            "code" to e.code,
                            "message" to e.message,
                            "detail" to e.detail,
                        )
                    )
                }
            } catch (e: Throwable) {
                if (cancelled) {
                    emit(mapOf("type" to "cancelled", "requestId" to requestId))
                } else {
                    val detail = (e.message ?: e.toString()).takeLast(2000)
                    val classified = classify(detail, url)
                    emit(
                        mapOf(
                            "type" to "error",
                            "requestId" to requestId,
                            "code" to classified.first,
                            "message" to classified.second,
                            "detail" to detail,
                        )
                    )
                }
            } finally {
                ffmpegProcess = null
                activeId = null
                globalBusy.set(false)
            }
        }, "save-and-send-download").start()
    }

    fun cancel() {
        cancelled = true
        activeId?.let { YoutubeDL.getInstance().destroyProcessById(it) }
        ffmpegProcess?.destroy()
    }

    private fun run(requestId: String, url: String, options: Options): Result {
        // The gallery has the saved copy, so old preview/share files are no
        // longer needed. Keep only this request's folder.
        val downloadsRoot = File(context.cacheDir, "downloads")
        downloadsRoot.listFiles()
            ?.filter { it.isDirectory && it.name != requestId }
            ?.forEach { old -> runCatching { old.deleteRecursively() } }

        val workDir = File(context.cacheDir, "downloads/$requestId")
        workDir.deleteRecursively()
        if (!workDir.mkdirs() && !workDir.isDirectory) {
            throw DownloadException("storage", "Couldn't create a temporary folder for the video.")
        }

        emit(mapOf("type" to "stage", "requestId" to requestId, "stage" to "preparing"))
        if (cancelled) throw YoutubeDL.CanceledException()

        if (options.audioOnly) {
            return runAudio(requestId, url, workDir)
        }

        val response = executeWithFallback(requestId, url, workDir, options)
        if (cancelled) throw YoutubeDL.CanceledException()

        emit(mapOf("type" to "stage", "requestId" to requestId, "stage" to "optimizing"))

        val raw = findDownloadedVideo(workDir)
            ?: throw DownloadException(
                "no_video",
                "The download finished but no video file was found.",
                response.err.takeLast(1500),
            )

        val infoJson = readInfoJson(workDir)
        var inspected = inspect(raw)
        if (inspected.durationMs <= 0) {
            val fromJson = (infoJson?.optDouble("duration", 0.0) ?: 0.0) * 1000
            if (fromJson > 0) inspected = inspected.copy(durationMs = fromJson.toLong())
        }

        if (cancelled) throw YoutubeDL.CanceledException()

        val trimmed = inspected.durationMs > 59_500
        val finalFile = prepare(raw, workDir, inspected, trimmed, requestId)
        if (cancelled) throw YoutubeDL.CanceledException()
        val finalInfo = inspect(finalFile)

        val title = infoJson?.optString("title")?.takeIf { it.isNotBlank() }
            ?: urlTitle(url)
        val thumbnailSource = workDir.listFiles()
            ?.filter { it.isFile && it.extension.lowercase() in IMAGE_EXTENSIONS }
            ?.maxByOrNull { it.length() }

        // Give the file the video's own name. The Gallery stays searchable and
        // the name WhatsApp shows is the title, not "final.mp4".
        val named = renameWithin(workDir, finalFile, title, "mp4")

        emit(mapOf("type" to "stage", "requestId" to requestId, "stage" to "saving"))
        if (cancelled) throw YoutubeDL.CanceledException()
        val saved = runCatching { saveToGallery(named, title, false) }.getOrDefault(emptyMap())
        val uri = saved["uri"] as? String
        if (saved["ok"] == true) {
            emit(mapOf("type" to "gallery", "requestId" to requestId, "saved" to true))
        }

        val thumbnail = keepThumbnail(thumbnailSource)

        val duration = when {
            finalInfo.durationMs > 0 -> finalInfo.durationMs
            inspected.durationMs > 0 -> if (trimmed) 59_500 else inspected.durationMs
            else -> 0
        }

        val jsonWidth = infoJson?.optInt("width", 0) ?: 0
        val jsonHeight = infoJson?.optInt("height", 0) ?: 0
        val width = when {
            finalInfo.displayWidth > 0 -> finalInfo.displayWidth
            jsonWidth > 0 -> jsonWidth
            else -> inspected.displayWidth
        }
        val height = when {
            finalInfo.displayHeight > 0 -> finalInfo.displayHeight
            jsonHeight > 0 -> jsonHeight
            else -> inspected.displayHeight
        }

        // Only the finished file and the tiny info file stay in cache.
        raw.delete()
        workDir.listFiles()?.forEach { file ->
            if (file != named && file.name != "video.info.json") {
                file.delete()
            }
        }

        return Result(
            file = named,
            title = title,
            durationMs = duration,
            width = width,
            height = height,
            hasAudio = finalInfo.hasAudio,
            thumbnail = thumbnail,
            thumbnailUrl = infoJson?.optString("thumbnail")?.takeIf { it.isNotBlank() },
            trimmed = trimmed,
            uri = uri,
            path = saved["path"] as? String,
            audioOnly = false,
        )
    }

    // ---------------------------------------------------------------------
    // Audio only
    // ---------------------------------------------------------------------

    private fun runAudio(requestId: String, url: String, workDir: File): Result {
        emit(mapOf("type" to "stage", "requestId" to requestId, "stage" to "downloading"))
        val clean = normalizeUrl(url)
        val referer = when {
            isInstagram(clean) -> "https://www.instagram.com/"
            isFacebook(clean) -> "https://www.facebook.com/"
            else -> null
        }

        fun fetch(request: YoutubeDLRequest) =
            YoutubeDL.getInstance().execute(request, requestId) { progress, eta, line ->
                onProgress(requestId, progress, eta, line)
            }

        var response = try {
            fetch(
                buildRequest(
                    clean,
                    workDir,
                    format = "ba[ext=m4a]/ba[ext=mp4]/ba/b",
                    referer = referer,
                )
            )
        } catch (e: Throwable) {
            if (cancelled) throw YoutubeDL.CanceledException()
            // Some sites only expose one muxed file. Download it and pull the
            // soundtrack out on the phone instead of failing.
            workDir.listFiles()?.forEach { file ->
                if (file.isFile && file.name != "video.info.json") file.delete()
            }
            try {
                fetch(
                    buildRequest(
                        clean,
                        workDir,
                        format = "b/best",
                        referer = referer,
                    )
                )
            } catch (second: Throwable) {
                val detail = second.message ?: second.toString()
                val classified = classify(detail, url)
                throw DownloadException(
                    classified.first,
                    classified.second,
                    detail.takeLast(1500),
                )
            }
        }
        if (cancelled) throw YoutubeDL.CanceledException()

        val source = findDownloadedAudio(workDir)
            ?: throw DownloadException(
                "no_video",
                "The download finished but no audio file was found.",
                response.err.takeLast(1200),
            )

        emit(mapOf("type" to "stage", "requestId" to requestId, "stage" to "optimizing"))
        val mp3 = File(workDir, "final.mp3")
        convertToMp3(source, mp3)
        if (cancelled) throw YoutubeDL.CanceledException()
        if (!mp3.exists() || mp3.length() == 0L) {
            throw DownloadException("processing", "Couldn't prepare the audio file.")
        }

        val infoJson = readInfoJson(workDir)
        val title = infoJson?.optString("title")?.takeIf { it.isNotBlank() }
            ?: urlTitle(url)
        val named = renameWithin(workDir, mp3, title, "mp3")
        val info = inspect(named)

        emit(mapOf("type" to "stage", "requestId" to requestId, "stage" to "saving"))
        if (cancelled) throw YoutubeDL.CanceledException()
        val saved = runCatching { saveToGallery(named, title, true) }.getOrDefault(emptyMap())
        if (saved["ok"] == true) {
            emit(mapOf("type" to "gallery", "requestId" to requestId, "saved" to true))
        }

        val thumbnail = keepThumbnail(
            workDir.listFiles()
                ?.filter { it.isFile && it.extension.lowercase() in IMAGE_EXTENSIONS }
                ?.maxByOrNull { it.length() },
        )

        source.delete()
        workDir.listFiles()?.forEach { file ->
            if (file != named && file.name != "video.info.json") file.delete()
        }

        return Result(
            file = named,
            title = title,
            durationMs = info.durationMs,
            width = 0,
            height = 0,
            hasAudio = true,
            thumbnail = thumbnail,
            thumbnailUrl = infoJson?.optString("thumbnail")?.takeIf { it.isNotBlank() },
            trimmed = false,
            uri = saved["uri"] as? String,
            path = saved["path"] as? String,
            audioOnly = true,
        )
    }

    private fun convertToMp3(input: File, output: File) {
        if (input.extension.equals("mp3", ignoreCase = true)) {
            input.copyTo(output, overwrite = true)
            return
        }
        val ffmpeg = ffmpegBinary()
            ?: throw IOException("FFmpeg is missing from the installation.")
        val command = listOf(
            ffmpeg.absolutePath,
            "-y",
            "-nostdin",
            "-hide_banner",
            "-loglevel", "error",
            "-i", input.absolutePath,
            "-vn",
            "-map_metadata", "-1",
            "-c:a", "libmp3lame",
            "-b:a", "192k",
            output.absolutePath,
        )
        val log = StringBuilder()
        if (!runFfmpegCommand(command, log) || !output.exists() || output.length() == 0L) {
            throw IOException("FFmpeg could not convert the audio: ${log.toString().takeLast(800)}")
        }
    }

    private fun findDownloadedAudio(workDir: File): File? {
        val files = workDir.listFiles()
            ?.filter {
                it.isFile && it.length() > 0L && !it.name.endsWith(".part")
            }
            ?.filter { it.name != "video.info.json" }
            ?: return null

        val audio = files
            .filter { it.extension.lowercase() in AUDIO_EXTENSIONS }
            .maxByOrNull { it.length() }
        if (audio != null) return audio

        // The site only had a muxed file; FFmpeg will pull the sound out of it.
        return files
            .filter { it.extension.lowercase() in VIDEO_EXTENSIONS }
            .maxByOrNull { it.length() }
    }

    // ---------------------------------------------------------------------
    // Probing formats before the download
    // ---------------------------------------------------------------------

    /** Reads title, duration and per-quality sizes without downloading the video. */
    fun probe(rawUrl: String): Probe {
        if (isBusy()) throw IllegalStateException("A download is already running.")
        if (!probeBusy.compareAndSet(false, true)) {
            throw IllegalStateException("A link check is already running.")
        }
        try {
            return probeLink(rawUrl)
        } finally {
            probeBusy.set(false)
        }
    }

    private fun probeLink(rawUrl: String): Probe {
        val url = normalizeUrl(rawUrl)
        val request = YoutubeDLRequest(url)
        request.addOption("-J")
        request.addOption("--no-playlist")
        request.addOption("--no-warnings")
        request.addOption("--socket-timeout", "20")
        request.addOption("--user-agent", USER_AGENT)

        if (isInstagram(url)) {
            request.addOption("--add-header", "Referer:https://www.instagram.com/")
        } else if (isFacebook(url)) {
            request.addOption("--add-header", "Referer:https://www.facebook.com/")
        }
        val cookies = cookiesFile()
        if (cookies.exists() && cookies.length() > 0L) {
            request.addOption("--cookies", cookies.absolutePath)
        }

        val response = YoutubeDL.getInstance().execute(request)
        val json = JSONObject(response.out)
        val durationSeconds = json.optDouble("duration", 0.0)
        val formats = json.optJSONArray("formats")

        var bestAudioSize = 0L
        var bestAudioRate = -1.0
        // height -> (bytes, isMp4, alreadyHasAudio)
        val byHeight = LinkedHashMap<Int, Triple<Long, Boolean, Boolean>>()

        if (formats != null) {
            for (index in 0 until formats.length()) {
                val format = formats.optJSONObject(index) ?: continue
                val vcodec = format.optString("vcodec", "none")
                val acodec = format.optString("acodec", "none")
                val size = formatSize(format, durationSeconds)
                val height = format.optInt("height", 0)

                if (vcodec == "none" && acodec != "none") {
                    val rate = format.optDouble("abr", 0.0)
                    if (rate >= bestAudioRate) {
                        bestAudioRate = rate
                        bestAudioSize = size
                    }
                    continue
                }
                if (vcodec == "none" || height <= 0 || height > 1080) continue

                // Prefer H.264/MP4 because that is what WhatsApp accepts.
                val isMp4 = format.optString("ext") == "mp4" || vcodec.startsWith("avc")
                val hasAudio = acodec != "none"
                val previous = byHeight[height]
                val better = previous == null ||
                    (isMp4 && !previous.second) ||
                    (isMp4 == previous.second && size > previous.first)
                if (better) byHeight[height] = Triple(size, isMp4, hasAudio)
            }
        }

        val options = mutableListOf<ProbeOption>()
        byHeight.entries
            .sortedByDescending { it.key }
            .take(5)
            .forEach { (height, value) ->
                val total = when {
                    value.first <= 0L -> 0L
                    value.third -> value.first
                    else -> value.first + bestAudioSize
                }
                options += ProbeOption(height = height, sizeBytes = total, audio = false)
            }
        if (bestAudioSize > 0L) {
            options += ProbeOption(height = 0, sizeBytes = bestAudioSize, audio = true)
        }
        if (options.none { !it.audio }) {
            options.add(0, ProbeOption(height = 0, sizeBytes = 0, audio = false))
        }

        return Probe(
            title = json.optString("title").takeIf { it.isNotBlank() } ?: urlTitle(url),
            durationMs = (durationSeconds * 1000).roundToLong(),
            thumbnailUrl = json.optString("thumbnail").takeIf { it.isNotBlank() },
            options = options,
        )
    }

    private fun formatSize(format: JSONObject, durationSeconds: Double): Long {
        val exact = format.optLong("filesize", 0L)
        if (exact > 0L) return exact
        val approx = format.optLong("filesize_approx", 0L)
        if (approx > 0L) return approx
        val tbr = format.optDouble("tbr", 0.0)
        if (tbr > 0.0 && durationSeconds > 0.0) {
            return (tbr * 1000.0 / 8.0 * durationSeconds).roundToLong()
        }
        return 0L
    }

    /** Redacted yt-dlp trace used by the diagnostics screen. */
    fun diagnose(rawUrl: String): String {
        val url = normalizeUrl(rawUrl)
        val request = YoutubeDLRequest(url)
        request.addOption("-v")
        request.addOption("--simulate")
        request.addOption("--no-playlist")
        request.addOption("--no-warnings")
        request.addOption("--socket-timeout", "20")
        request.addOption("--user-agent", USER_AGENT)
        if (isInstagram(url)) {
            request.addOption("--add-header", "Referer:https://www.instagram.com/")
        } else if (isFacebook(url)) {
            request.addOption("--add-header", "Referer:https://www.facebook.com/")
        }
        val cookies = cookiesFile()
        if (cookies.exists() && cookies.length() > 0L) {
            request.addOption("--cookies", cookies.absolutePath)
        }

        val response = runCatching { YoutubeDL.getInstance().execute(request) }
        val body = response.map { "${it.out}\n${it.err}" }
            .getOrElse { it.message ?: it.toString() }
        val text = buildString {
            appendLine("yt-dlp ${runCatching { YoutubeDL.versionName(context) }.getOrNull() ?: "?"}")
            appendLine("url: $url")
            appendLine(body.takeLast(14_000))
        }
        return redact(text)
    }

    private fun redact(text: String): String {
        var clean = text
        listOf(
            cookiesFile().absolutePath,
            context.filesDir.absolutePath,
            context.cacheDir.absolutePath,
            context.applicationInfo.nativeLibraryDir,
        ).forEach { path ->
            if (path.isNotBlank()) clean = clean.replace(path, "<app>")
        }
        return clean
            .lineSequence()
            .filterNot { line ->
                val lower = line.lowercase()
                lower.contains("cookie:") || lower.contains("set-cookie")
            }
            .joinToString("\n")
    }

    // ---------------------------------------------------------------------
    // Naming and thumbnails
    // ---------------------------------------------------------------------

    private fun urlTitle(url: String): String {
        val id = url.substringAfterLast('/').substringBefore('?').take(40)
        return id.takeIf { it.isNotBlank() } ?: "Video"
    }

    private fun sanitizeName(raw: String): String {
        val cleaned = raw
            .replace(Regex("[\\/:*?\"<>|\u0000-\u001F]"), " ")
            .replace(Regex("\\s+"), " ")
            .trim()
            .trim('.', ' ')
            .take(80)
            .trim()
        return cleaned.ifBlank { "Save & Send video" }
    }

    private fun renameWithin(dir: File, file: File, rawTitle: String, extension: String): File {
        val name = sanitizeName(rawTitle)
        var candidate = File(dir, "$name.$extension")
        var counter = 2
        while (candidate.exists() && candidate != file) {
            candidate = File(dir, "$name ($counter).$extension")
            counter += 1
        }
        if (candidate == file) return file
        return if (runCatching { file.renameTo(candidate) }.getOrDefault(false)) candidate else file
    }

    private fun keepThumbnail(source: File?): File? {
        if (source == null || !source.exists() || source.length() == 0L) return null
        val dir = File(context.filesDir, "history").apply { mkdirs() }
        val extension = source.extension.ifBlank { "jpg" }
        val target = File(dir, "thumb_${System.currentTimeMillis()}.$extension")
        val copied = runCatching { source.copyTo(target, overwrite = true) }
            .getOrDefault(source)
        runCatching {
            dir.listFiles()
                ?.filter { it.isFile && it.name.startsWith("thumb_") }
                ?.sortedBy { it.lastModified() }
                ?.dropLast(60)
                ?.forEach { it.delete() }
        }
        return copied
    }

    // ---------------------------------------------------------------------
    // yt-dlp
    // ---------------------------------------------------------------------

    private fun executeWithFallback(
        requestId: String,
        rawUrl: String,
        workDir: File,
        options: Options,
    ): com.yausername.youtubedl_android.YoutubeDLResponse {
        val url = normalizeUrl(rawUrl)
        val preferredFormat = videoFormat(options.maxHeight)
        val attempts = mutableListOf<Pair<String, YoutubeDLRequest>>()

        if (isFacebook(url)) {
            // Facebook streams are tagged 'hd' or 'sd' with unknown resolution.
            // Match these first so yt-dlp doesn't fail looking for specific heights.
            attempts += "facebook-default" to buildRequest(
                url,
                workDir,
                format = "best[ext=mp4]/bestvideo+bestaudio/best/b",
                referer = "https://www.facebook.com/",
            )
            attempts += "facebook-alt" to buildRequest(
                url,
                workDir,
                format = "b/best",
                referer = "https://www.facebook.com/",
            )
        } else if (isYouTube(url)) {
            attempts += "youtube-default" to buildRequest(url, workDir, format = preferredFormat)
            attempts += "youtube-alt" to buildRequest(
                url,
                workDir,
                youtubeClient = "android_vr,web_safari,tv",
            )
            // YouTube rotates its player responses constantly. Another client
            // set costs nothing when the first two fail and often recovers a
            // blocked video without touching cookies.
            attempts += "youtube-embedded" to buildRequest(
                url,
                workDir,
                youtubeClient = "tv_simply,web_embedded,mweb",
            )
            attempts += "youtube-fallback" to buildRequest(url, workDir, format = "b")
        } else if (isInstagram(url)) {
            attempts += "instagram-default" to buildRequest(url, workDir, format = preferredFormat)
            attempts += "instagram-alt" to buildRequest(
                url,
                workDir,
                format = "best[ext=mp4]/bestvideo+bestaudio/best",
                referer = "https://www.instagram.com/",
            )
            attempts += "instagram-fallback" to buildRequest(url, workDir, format = "b")
        } else {
            attempts += "default" to buildRequest(url, workDir, format = preferredFormat)
            attempts += "fallback" to buildRequest(url, workDir, format = "b")
        }

        // "Try another method" skips the client set that just failed.
        val queue = if (options.alternate && attempts.size > 1) attempts.drop(1) else attempts

        var lastError: Throwable? = null
        queue.forEachIndexed { index, (label, request) ->
            if (cancelled) throw YoutubeDL.CanceledException()
            if (index > 0) {
                workDir.deleteRecursively()
                workDir.mkdirs()
                emit(
                    mapOf(
                        "type" to "stage",
                        "requestId" to requestId,
                        "stage" to "retrying",
                        "attempt" to label,
                    )
                )
            }
            try {
                return YoutubeDL.getInstance().execute(request, requestId) { progress, eta, line ->
                    onProgress(requestId, progress, eta, line)
                }
            } catch (e: YoutubeDL.CanceledException) {
                throw e
            } catch (e: Throwable) {
                lastError = e
                val message = (e.message ?: "").lowercase()
                val retryable = when {
                    message.contains("login required") ||
                        message.contains("requested content is not available") ||
                        message.contains("rate-limit") ||
                        message.contains("private") ||
                        message.contains("video unavailable") ||
                        message.contains("unsupported url") -> false

                    isYouTube(url) && (
                        message.contains("sign in to confirm") ||
                            message.contains("not a bot") ||
                            message.contains("http error 403")
                        ) -> true

                    (isInstagram(url) || isFacebook(url)) && (
                        message.contains("http error 401") ||
                            message.contains("http error 403") ||
                            message.contains("redirect") ||
                            message.contains("no video formats") ||
                            message.contains("unable to extract")
                        ) -> true

                    message.contains("requested format is not available") ||
                        message.contains("no video formats found") ||
                        message.contains("unable to extract") ||
                        message.contains("some formats may be missing") -> true

                    else -> false
                }
                if (!retryable) throw e
            }
        }
        throw lastError ?: IllegalStateException("Download failed")
    }

    private fun buildRequest(
        url: String,
        workDir: File,
        format: String = FORMAT,
        youtubeClient: String? = null,
        customUserAgent: String? = null,
        referer: String? = null,
    ): YoutubeDLRequest {
        val request = YoutubeDLRequest(url)
        request.addOption("-f", format)
        request.addOption("--merge-output-format", "mp4")
        request.addOption("--no-playlist")
        request.addOption("--no-mtime")
        request.addOption("--newline")
        request.addOption("--write-info-json")
        request.addOption("--write-thumbnail")
        request.addOption("--retries", 3)
        request.addOption("--fragment-retries", 3)
        request.addOption("--concurrent-fragments", 4)
        request.addOption("--socket-timeout", 20)
        request.addOption("--restrict-filenames")
        request.addOption("-o", File(workDir, "video.%(ext)s").absolutePath)

        val ua = customUserAgent ?: USER_AGENT
        request.addOption("--user-agent", ua)

        if (referer != null) {
            request.addOption("--add-header", "Referer:$referer")
        } else if (isInstagram(url)) {
            request.addOption("--add-header", "Referer:https://www.instagram.com/")
        } else if (isFacebook(url)) {
            request.addOption("--add-header", "Referer:https://www.facebook.com/")
        }

        val cookies = cookiesFile()
        if (cookies.exists() && cookies.length() > 0L) {
            request.addOption("--cookies", cookies.absolutePath)
        }
        if (youtubeClient != null) {
            request.addOption("--extractor-args", "youtube:player_client=$youtubeClient")
        }
        return request
    }

    private fun onProgress(requestId: String, rawProgress: Float, eta: Long, line: String) {
        if (cancelled) return
        val progress = rawProgress.coerceIn(0f, 100f)
        if (progress >= 0f && rawProgress >= 0f) {
            emit(
                mapOf(
                    "type" to "progress",
                    "requestId" to requestId,
                    "percent" to progress.toDouble(),
                    "etaSeconds" to eta,
                )
            )
        }
        val lower = line.lowercase()
        val stage = when {
            lower.contains("[merger]") || lower.contains("[videoremuxer]") -> "merging"
            lower.contains("[videoconvertor]") || lower.contains("[extractaudio]") -> "optimizing"
            lower.contains("destination:") && (
                lower.contains(".m4a") ||
                    lower.contains(".opus") ||
                    lower.contains("audio")
                ) -> "audio"
            lower.contains("destination:") -> "downloading"
            else -> null
        }
        if (stage != null) {
            emit(mapOf("type" to "stage", "requestId" to requestId, "stage" to stage))
        }
    }

    // ---------------------------------------------------------------------
    // Post-processing
    // ---------------------------------------------------------------------

    private fun prepare(
        raw: File,
        workDir: File,
        info: Inspected,
        trimmed: Boolean,
        requestId: String,
    ): File {
        val output = File(workDir, "final.mp4")
        val downscale = max(info.displayWidth, info.displayHeight) > 1920
        val incompatibleVideo = info.videoMime != "video/avc"
        val incompatibleAudio = info.hasAudio && (
            info.audioMime != "audio/mp4a-latm" || info.audioChannels > 2
            )
        val wrongContainer = raw.extension.lowercase() !in setOf("mp4", "m4v", "mov")
        val reencode = incompatibleVideo || incompatibleAudio || wrongContainer || downscale || trimmed

        emit(
            mapOf(
                "type" to "stage",
                "requestId" to requestId,
                "stage" to if (trimmed) "trimming" else "optimizing",
            )
        )

        if (reencode) {
            try {
                runFfmpeg(raw, output, info, reencode = true, trim = trimmed, downscale = downscale)
            } catch (e: Exception) {
                if (cancelled) throw YoutubeDL.CanceledException()
                // Fallback 1: Stream copy with trimming if needed
                val streamCopyOk = runCatching {
                    runFfmpeg(raw, output, info, reencode = false, trim = trimmed, downscale = false)
                }.isSuccess

                if (!streamCopyOk) {
                    if (cancelled) throw YoutubeDL.CanceledException()
                    // Fallback 2: Direct raw copy so the downloaded video is never lost
                    if (raw.exists() && raw.length() > 0L) {
                        raw.copyTo(output, overwrite = true)
                    } else {
                        throw DownloadException(
                            "processing",
                            "Couldn't prepare the video for WhatsApp.",
                            e.message,
                        )
                    }
                }
            }
        } else {
            try {
                runFfmpeg(raw, output, info, reencode = false, trim = false, downscale = false)
            } catch (e: Exception) {
                if (cancelled) throw YoutubeDL.CanceledException()
                // A plain copy still works if FFmpeg refuses to remux.
                raw.copyTo(output, overwrite = true)
            }
        }

        if (!output.exists() || output.length() == 0L) {
            throw DownloadException("processing", "The video file is empty.")
        }
        return output
    }

    private fun isCompatible(file: File, info: Inspected): Boolean {
        return info.videoMime == "video/avc" &&
            (!info.hasAudio || (info.audioMime == "audio/mp4a-latm" && info.audioChannels <= 2)) &&
            file.extension.lowercase() in setOf("mp4", "m4v", "mov") &&
            info.durationMs <= 59_500 &&
            max(info.displayWidth, info.displayHeight) <= 1920
    }

    private fun ffmpegBinary(): File? {
        val ffmpeg = File(context.applicationInfo.nativeLibraryDir, "libffmpeg.so")
        if (!ffmpeg.exists()) return null
        if (!ffmpeg.canExecute()) {
            // Native libraries are normally extracted executable, but some
            // installers do not preserve the mode. Failure here is harmless.
            ffmpeg.setExecutable(true)
        }
        return ffmpeg
    }

    /**
     * Runs FFmpeg and collects its output. Returns true on a clean exit.
     * The process is exposed through [ffmpegProcess] so cancel() can kill it.
     */
    private fun runFfmpegCommand(command: List<String>, outputText: StringBuilder): Boolean {
        NativeLibraryHelper.fixDependencies(context)

        val processBuilder = ProcessBuilder(command)
        processBuilder.environment().apply {
            this["LD_LIBRARY_PATH"] = NativeLibraryHelper.getLdLibraryPath(context)
            this["HOME"] = context.cacheDir.absolutePath
            this["TMPDIR"] = context.cacheDir.absolutePath
        }
        processBuilder.redirectErrorStream(true)

        val process = processBuilder.start()
        ffmpegProcess = process
        val reader = Thread {
            runCatching {
                process.inputStream.bufferedReader().useLines { lines ->
                    lines.forEach { outputText.appendLine(it) }
                }
            }
        }
        reader.start()

        val finished = process.waitFor(10, TimeUnit.MINUTES)
        if (!finished) {
            process.destroyForcibly()
            ffmpegProcess = null
            throw IOException("FFmpeg timed out.")
        }
        reader.join(2_000)
        ffmpegProcess = null
        return process.exitValue() == 0
    }

    /**
     * Merges a left-over video-only file with its separate audio track. This is
     * the rescue path for downloads where yt-dlp could not run its own merge
     * step and the soundtrack was otherwise silently dropped.
     */
    private fun muxSeparateStreams(video: File, audio: File, output: File): Boolean {
        val ffmpeg = ffmpegBinary() ?: return false
        val command = listOf(
            ffmpeg.absolutePath,
            "-y",
            "-nostdin",
            "-hide_banner",
            "-loglevel", "error",
            "-i", video.absolutePath,
            "-i", audio.absolutePath,
            "-map", "0:v:0",
            "-map", "1:a:0",
            "-c:v", "copy",
            "-c:a", "aac",
            "-b:a", "128k",
            "-ac", "2",
            "-movflags", "+faststart",
            output.absolutePath,
        )
        val ok = runCatching { runFfmpegCommand(command, StringBuilder()) }.getOrDefault(false)
        if (ok && output.length() > 0L && inspect(output).hasAudio) return true
        runCatching { output.delete() }
        return false
    }

    private fun runFfmpeg(
        input: File,
        output: File,
        info: Inspected,
        reencode: Boolean,
        trim: Boolean,
        downscale: Boolean,
    ) {
        val ffmpeg = ffmpegBinary()
            ?: throw IOException("FFmpeg is missing from the installation.")

        val command = mutableListOf(
            ffmpeg.absolutePath,
            "-y",
            "-nostdin",
            "-hide_banner",
            "-loglevel", "error",
            "-i", input.absolutePath,
            "-map", "0:v:0",
            // Keep an audio stream even if MediaExtractor could not index the
            // file. The "?" makes the map optional for genuinely silent videos.
            "-map", "0:a:0?",
        )
        if (trim) {
            command += listOf("-t", "59.5")
        }
        if (reencode) {
            command += listOf(
                "-c:v", "libx264",
                "-preset", "veryfast",
                "-crf", "23",
                "-pix_fmt", "yuv420p",
            )
            if (downscale) {
                val filter = if (info.displayWidth >= info.displayHeight) {
                    "scale=-2:1080"
                } else {
                    "scale=1080:-2"
                }
                command += listOf("-vf", filter)
            }
            if (info.hasAudio) {
                command += listOf("-c:a", "aac", "-b:a", "128k", "-ac", "2")
            }
        } else {
            command += listOf("-c", "copy")
        }
        command += listOf("-movflags", "+faststart", output.absolutePath)

        val outputText = StringBuilder()
        val ok = runFfmpegCommand(command, outputText)

        if (!ok || !output.exists() || output.length() == 0L) {
            throw IOException("FFmpeg failed: ${outputText.toString().takeLast(1200)}")
        }
    }

    private fun inspect(file: File): Inspected {
        var duration = 0L
        var width = 0
        var height = 0
        var rotation = 0
        val retriever = MediaMetadataRetriever()
        try {
            retriever.setDataSource(file.absolutePath)
            duration = retriever.extractMetadata(MediaMetadataRetriever.METADATA_KEY_DURATION)
                ?.toLongOrNull() ?: 0L
            width = retriever.extractMetadata(MediaMetadataRetriever.METADATA_KEY_VIDEO_WIDTH)
                ?.toIntOrNull() ?: 0
            height = retriever.extractMetadata(MediaMetadataRetriever.METADATA_KEY_VIDEO_HEIGHT)
                ?.toIntOrNull() ?: 0
            rotation = retriever.extractMetadata(MediaMetadataRetriever.METADATA_KEY_VIDEO_ROTATION)
                ?.toIntOrNull() ?: 0
        } catch (_: Exception) {
            // Fall through to MediaExtractor / metadata JSON.
        } finally {
            runCatching { retriever.release() }
        }

        var hasAudio = false
        var videoMime: String? = null
        var audioMime: String? = null
        var audioChannels = 0
        val extractor = MediaExtractor()
        try {
            extractor.setDataSource(file.absolutePath)
            for (index in 0 until extractor.trackCount) {
                val format = extractor.getTrackFormat(index)
                val mime = format.getString(MediaFormat.KEY_MIME) ?: continue
                if (mime.startsWith("video/")) {
                    if (videoMime == null) {
                        videoMime = mime
                        if (width <= 0) width = format.optInt(MediaFormat.KEY_WIDTH)
                        if (height <= 0) height = format.optInt(MediaFormat.KEY_HEIGHT)
                    }
                } else if (mime.startsWith("audio/")) {
                    if (!hasAudio) {
                        hasAudio = true
                        audioMime = mime
                        audioChannels = format.optInt(MediaFormat.KEY_CHANNEL_COUNT)
                    }
                }
            }
        } catch (_: Exception) {
            // A file that Android cannot index is handled by FFmpeg.
        } finally {
            runCatching { extractor.release() }
        }

        return Inspected(
            durationMs = duration,
            width = width,
            height = height,
            rotation = rotation,
            hasAudio = hasAudio,
            videoMime = videoMime,
            audioMime = audioMime,
            audioChannels = audioChannels,
        )
    }

    private fun MediaFormat.optInt(key: String): Int {
        return runCatching {
            if (containsKey(key)) getInteger(key) else 0
        }.getOrDefault(0)
    }

    private fun findDownloadedVideo(workDir: File): File? {
        // The output template is video.%(ext)s. When yt-dlp merges separate
        // streams it writes the finished file as video.mp4 and leaves the
        // temporary video-only/audio files with format IDs in their names.
        val merged = File(workDir, "video.mp4")
        if (merged.isFile && merged.length() > 0L) return merged

        val files = workDir.listFiles()
            ?.filter { it.isFile && it.length() > 0L && !it.name.endsWith(".part") }
            .orEmpty()
        val video = files
            .filter { it.extension.lowercase() in VIDEO_EXTENSIONS }
            .maxByOrNull { it.length() }
            ?: return null

        // A failed or skipped merge leaves the soundtrack as its own file. Mux
        // it back instead of quietly handing back a silent video.
        val audio = files
            .filter { it.extension.lowercase() in AUDIO_EXTENSIONS }
            .maxByOrNull { it.length() }

        if (audio != null) {
            val muxed = File(workDir, "video.mp4")
            if (muxSeparateStreams(video, audio, muxed)) return muxed
        }
        return video
    }

    private fun readInfoJson(workDir: File): JSONObject? {
        val file = File(workDir, "video.info.json")
        if (!file.exists()) return null
        return runCatching { JSONObject(file.readText()) }.getOrNull()
    }

    private fun cookiesFile(): File = File(context.filesDir, "cookies.txt")

    private fun isYouTube(url: String): Boolean {
        val lower = url.lowercase()
        return lower.contains("youtube.com") ||
            lower.contains("youtu.be") ||
            lower.contains("youtube-nocookie.com")
    }

    private fun isInstagram(url: String): Boolean {
        val lower = url.lowercase()
        return lower.contains("instagram.com") ||
            lower.contains("instagr.am") ||
            lower.contains("ig.me")
    }

    private fun isFacebook(url: String): Boolean {
        val lower = url.lowercase()
        return lower.contains("facebook.com") ||
            lower.contains("fb.watch") ||
            lower.contains("fb.com")
    }

    private fun normalizeUrl(url: String): String {
        val clean = url.trim()
        val instaShare = Regex("""(?:https?://)?(?:www\.)?instagram\.com/share/(reel|reels|p|tv)/([^/?#&]+)""", RegexOption.IGNORE_CASE)
            .find(clean)
        if (instaShare != null) {
            val type = instaShare.groupValues[1].let { if (it.equals("reels", ignoreCase = true)) "reel" else it }
            val id = instaShare.groupValues[2]
            return "https://www.instagram.com/$type/$id/"
        }

        // Direct digit links (canonical numeric IDs)
        val fbShareReel = Regex("""(?:https?://)?(?:www\.|m\.)?facebook\.com/share/r/([^/?#&]+)""", RegexOption.IGNORE_CASE)
            .find(clean)
        if (fbShareReel != null && fbShareReel.groupValues[1].all { it.isDigit() }) {
            val id = fbShareReel.groupValues[1]
            return "https://www.facebook.com/reel/$id/"
        }

        val fbShareVideo = Regex("""(?:https?://)?(?:www\.|m\.)?facebook\.com/share/v/([^/?#&]+)""", RegexOption.IGNORE_CASE)
            .find(clean)
        if (fbShareVideo != null && fbShareVideo.groupValues[1].all { it.isDigit() }) {
            val id = fbShareVideo.groupValues[1]
            return "https://www.facebook.com/watch/?v=$id"
        }

        // Facebook mobile share links (e.g. /share/r/TOKEN) or fb.watch shortlinks
        if (clean.contains("fb.watch", ignoreCase = true) ||
            clean.contains("facebook.com/share", ignoreCase = true)
        ) {
            val resolved = resolveFacebookUrl(clean)
            if (resolved != clean) {
                return normalizeUrl(resolved)
            }
        }

        // Reddit share links (reddit.com/r/x/s/AbCdEf) are redirects, not
        // post URLs. Follow them once so yt-dlp gets something it can parse.
        if (clean.contains("reddit.com", ignoreCase = true) && clean.contains("/s/")) {
            val resolved = resolveRedirect(clean)
            if (resolved != clean) return normalizeUrl(resolved)
        }

        return clean
    }

    private fun resolveRedirect(rawUrl: String): String {
        return runCatching {
            var current = if (rawUrl.startsWith("http", ignoreCase = true)) rawUrl else "https://$rawUrl"
            for (hop in 0 until 5) {
                val conn = (java.net.URL(current).openConnection() as java.net.HttpURLConnection).apply {
                    instanceFollowRedirects = false
                    requestMethod = "HEAD"
                    connectTimeout = 4000
                    readTimeout = 4000
                    setRequestProperty("User-Agent", USER_AGENT)
                }
                conn.connect()
                val code = conn.responseCode
                val location = conn.getHeaderField("Location")
                conn.disconnect()
                if (code in 300..399 && !location.isNullOrBlank()) {
                    current = if (location.startsWith("http", ignoreCase = true)) {
                        location
                    } else {
                        java.net.URL(java.net.URL(current), location).toString()
                    }
                } else {
                    return@runCatching current
                }
            }
            current
        }.getOrDefault(rawUrl)
    }

    private fun resolveFacebookUrl(rawUrl: String): String {
        return runCatching {
            var currentUrl = if (rawUrl.startsWith("http", ignoreCase = true)) rawUrl else "https://$rawUrl"
            val ua = "facebookexternalhit/1.1 (+http://www.facebook.com/externalhit_uatext.php)"

            for (hop in 0 until 6) {
                val conn = (java.net.URL(currentUrl).openConnection() as java.net.HttpURLConnection).apply {
                    instanceFollowRedirects = false
                    requestMethod = "GET"
                    connectTimeout = 4000
                    readTimeout = 4000
                    setRequestProperty("User-Agent", ua)
                    setRequestProperty("Accept", "text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8")
                    setRequestProperty("Accept-Language", "en-US,en;q=0.9")
                }
                conn.connect()
                val code = conn.responseCode
                if (code in 300..399) {
                    val location = conn.getHeaderField("Location")
                    conn.disconnect()
                    if (!location.isNullOrBlank()) {
                        val nextUrl = if (location.startsWith("http", ignoreCase = true)) {
                            location
                        } else {
                            java.net.URL(java.net.URL(currentUrl), location).toString()
                        }
                        val reelMatch = Regex("""facebook\.com/(?:reel|reels)/(\d+)""", RegexOption.IGNORE_CASE).find(nextUrl)
                        if (reelMatch != null) {
                            return@runCatching "https://www.facebook.com/reel/${reelMatch.groupValues[1]}/"
                        }
                        val watchMatch = Regex("""facebook\.com/(?:watch/\?v=|videos/)(\d+)""", RegexOption.IGNORE_CASE).find(nextUrl)
                        if (watchMatch != null) {
                            return@runCatching "https://www.facebook.com/watch/?v=${watchMatch.groupValues[1]}"
                        }
                        currentUrl = nextUrl
                        continue
                    } else {
                        break
                    }
                } else if (code in 200..299) {
                    val html = conn.inputStream.bufferedReader().use { reader ->
                        val buffer = CharArray(65536)
                        val readChars = reader.read(buffer, 0, 65536)
                        if (readChars > 0) String(buffer, 0, readChars) else ""
                    }
                    conn.disconnect()

                    val ogMatch = Regex("""<meta[^>]+(?:property=["']og:url["'][^>]+content=["']([^"']+)["']|content=["']([^"']+)["'][^>]+property=["']og:url["'])""", RegexOption.IGNORE_CASE).find(html)
                    val ogUrl = ogMatch?.groupValues?.getOrNull(1)?.takeIf { it.isNotBlank() }
                        ?: ogMatch?.groupValues?.getOrNull(2)?.takeIf { it.isNotBlank() }

                    val canonMatch = Regex("""<link[^>]+(?:rel=["']canonical["'][^>]+href=["']([^"']+)["']|href=["']([^"']+)["'][^>]+rel=["']canonical["'])""", RegexOption.IGNORE_CASE).find(html)
                    val canonUrl = canonMatch?.groupValues?.getOrNull(1)?.takeIf { it.isNotBlank() }
                        ?: canonMatch?.groupValues?.getOrNull(2)?.takeIf { it.isNotBlank() }

                    val candidate = ogUrl ?: canonUrl ?: currentUrl

                    val reelMatch = Regex("""facebook\.com/(?:reel|reels)/(\d+)""", RegexOption.IGNORE_CASE).find(candidate)
                    if (reelMatch != null) {
                        return@runCatching "https://www.facebook.com/reel/${reelMatch.groupValues[1]}/"
                    }
                    val watchMatch = Regex("""facebook\.com/(?:watch/\?v=|videos/)(\d+)""", RegexOption.IGNORE_CASE).find(candidate)
                    if (watchMatch != null) {
                        return@runCatching "https://www.facebook.com/watch/?v=${watchMatch.groupValues[1]}"
                    }

                    val anyReel = Regex("""https?://(?:www\.|m\.)?facebook\.com/(?:reel|reels)/(\d+)""", RegexOption.IGNORE_CASE).find(html)
                    if (anyReel != null) {
                        return@runCatching "https://www.facebook.com/reel/${anyReel.groupValues[1]}/"
                    }
                    val anyWatch = Regex("""https?://(?:www\.|m\.)?facebook\.com/(?:watch/\?v=|[^"'\s]+/videos/)(\d+)""", RegexOption.IGNORE_CASE).find(html)
                    if (anyWatch != null) {
                        return@runCatching "https://www.facebook.com/watch/?v=${anyWatch.groupValues[1]}"
                    }

                    if (ogUrl != null && !ogUrl.contains("/share/")) {
                        return@runCatching ogUrl
                    }
                    break
                } else {
                    conn.disconnect()
                    break
                }
            }
            currentUrl
        }.getOrDefault(rawUrl)
    }

    private fun classify(detail: String, url: String): Pair<String, String> {
        val text = detail.lowercase()
        val instagram = isInstagram(url)
        val facebook = isFacebook(url)
        val youtube = isYouTube(url)

        return when {
            text.contains("age-restricted") ||
                text.contains("confirm your age") ||
                (text.contains("age") && (text.contains("confirm") || text.contains("restricted"))) ->
                "age" to "This video is age-restricted and can't be downloaded without a login."

            text.contains("sign in to confirm") ||
                text.contains("not a bot") ||
                (youtube && text.contains("http error 403")) ||
                (youtube && (
                    text.contains("nsig") ||
                        text.contains("signature extraction") ||
                        text.contains("some formats may be missing") ||
                        text.contains("unable to extract")
                    )) ->
                "youtube_block" to "YouTube is blocking this download right now. Update the downloader in Settings and try again."

            text.contains("login required") ||
                text.contains("requested content is not available") ||
                text.contains("rate-limit") ||
                text.contains("empty media response") ||
                text.contains("api is not granting access") ||
                text.contains("checking post accessibility") ||
                text.contains("http error 401") ||
                text.contains("http error 403") ||
                text.contains("cookies") ||
                text.contains("logged-in") ->
                when {
                    instagram -> "login" to "Instagram needs a login for this video. Add cookies in Settings, or try a public reel."
                    facebook -> "login" to "Facebook needs a login for this video or it is set to Friends-only. Add cookies in Settings, or try a public video."
                    else -> "login" to "This video needs a login. Only public videos can be downloaded."
                }

            text.contains("private") ||
                text.contains("only available for registered users") ||
                text.contains("friends") ->
                "private" to "This video is private. Only public videos can be downloaded."

            text.contains("unsupported url") || text.contains("no suitable") ->
                "unsupported" to "This link isn't supported."

            text.contains("video unavailable") ||
                text.contains("this video is unavailable") ||
                text.contains("removed by the uploader") ->
                "unavailable" to "This video is no longer available."

            // Check tool failures before the generic "not found" rule: an
            // error like "ffmpeg not found" is a processing problem.
            text.contains("ffmpeg") ||
                text.contains("postprocessing") ||
                text.contains("post-processing") ->
                "processing" to "The video downloaded, but it couldn't be prepared. Try again."

            text.contains("http error 404") || text.contains("not found") ->
                "not_found" to "This video couldn't be found. The link may have expired."

            text.contains("drm") || text.contains("protected") ->
                "drm" to "This video is protected and can't be downloaded."

            text.contains("unable to download webpage") ||
                text.contains("failed to resolve") ||
                text.contains("name or service not known") ||
                text.contains("network is unreachable") ||
                text.contains("connection") ||
                text.contains("timed out") ||
                text.contains("timeout") ->
                "network" to "No internet connection. Check your connection and try again."

            text.contains("no video formats") || text.contains("requested format") ->
                "no_video" to "No downloadable video was found at this link."

            text.contains("no space left") ||
                text.contains("enospc") ||
                text.contains("not enough space") ->
                "storage" to "There isn't enough storage space for this video."

            else ->
                "generic" to "Couldn't download this video. It may be private, deleted, or the link may be wrong."
        }
    }

    private fun videoFormat(maxHeight: Int): String {
        if (maxHeight <= 0) return FORMAT
        val height = maxHeight.coerceIn(144, 1920)
        return "bv*[height<=$height][vcodec^=avc1]+ba[acodec^=mp4a]/" +
            "b[height<=$height][ext=mp4]/" +
            "bv*[height<=$height]+ba/" +
            "b[height<=$height]/b"
    }

    companion object {
        /** One download at a time even if Android created two activity instances. */
        private val globalBusy = AtomicBoolean(false)

        private val VIDEO_EXTENSIONS = setOf("mp4", "m4v", "mov", "webm", "mkv", "avi")
        private val AUDIO_EXTENSIONS = setOf("m4a", "aac", "opus", "ogg", "mp3", "weba")
        private val IMAGE_EXTENSIONS = setOf("jpg", "jpeg", "png", "webp")

        const val USER_AGENT =
            "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 " +
                "(KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36"

        /**
         * Prefer H.264 + AAC (instantly playable by WhatsApp) at up to 1080p
         * in either orientation, then muxed MP4, then best progressive MP4 (Facebook/Instagram), then anything, then best.
         */
        private const val FORMAT =
            "bv*[width<=1920][height<=1920][vcodec^=avc1]+ba[acodec^=mp4a]/" +
                "b[width<=1920][height<=1920][ext=mp4]/" +
                "best[ext=mp4]/" +
                "bv*[width<=1920][height<=1920]+ba/" +
                "b[width<=1920][height<=1920]/b"
    }
}
