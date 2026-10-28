package com.personal.save_and_send

import android.Manifest
import android.content.ClipData
import android.content.ContentValues
import android.content.Intent
import android.content.pm.PackageManager
import android.media.MediaScannerConnection
import android.net.ConnectivityManager
import android.net.NetworkCapabilities
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.os.Environment
import android.os.Handler
import android.os.Looper
import android.provider.MediaStore
import android.view.WindowManager
import androidx.core.content.ContextCompat
import androidx.core.content.FileProvider
import com.yausername.ffmpeg.FFmpeg
import com.yausername.youtubedl_android.YoutubeDL
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.text.SimpleDateFormat
import java.util.ArrayDeque
import java.util.Date
import java.util.Locale
import java.util.concurrent.Executors

class MainActivity : FlutterActivity() {

    companion object {
        private const val METHOD_CHANNEL = "com.personal.save_and_send/native"
        private const val EVENT_CHANNEL = "com.personal.save_and_send/events"
        private const val PREFS = "save_and_send"
        private const val STATUS_REQUEST = 7001
        private const val STORAGE_REQUEST = 7002
    }

    private val mainHandler = Handler(Looper.getMainLooper())
    private val io = Executors.newSingleThreadExecutor()

    private var eventSink: EventChannel.EventSink? = null
    private val pendingEvents = ArrayDeque<Map<String, Any?>>()
    private var flutterStarted = false
    private var pendingShare: String? = null
    private var pendingShareError: String? = null

    @Volatile private var engineReady = false

    private val downloader: Downloader by lazy {
        Downloader(applicationContext, ::emitEvent, ::saveMediaToGallery)
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)

        if (savedInstanceState == null) {
            handleShareIntent(intent)
        }

        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.Q &&
            ContextCompat.checkSelfPermission(
                this,
                Manifest.permission.WRITE_EXTERNAL_STORAGE,
            ) != PackageManager.PERMISSION_GRANTED
        ) {
            requestPermissions(
                arrayOf(Manifest.permission.WRITE_EXTERNAL_STORAGE),
                STORAGE_REQUEST,
            )
        }

        // Warm up Python + FFmpeg while the first Flutter frame is drawn.
        io.execute { runCatching { ensureEngineReady() } }
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, METHOD_CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "getInitialShare" -> {
                        flutterStarted = true
                        result.success(
                            mapOf(
                                "url" to pendingShare,
                                "error" to pendingShareError,
                            )
                        )
                        pendingShare = null
                        pendingShareError = null
                    }

                    "ensureEngine" -> ensureEngine(result)

                    "download" -> {
                        val url = call.argument<String>("url")
                        val requestId = call.argument<String>("requestId")
                        if (url.isNullOrBlank() || requestId.isNullOrBlank()) {
                            result.error("BAD_ARGS", "A link and request ID are required.", null)
                        } else if (downloader.isBusy()) {
                            result.error("BUSY", "Another download is already running.", null)
                        } else {
                            io.execute {
                                try {
                                    ensureEngineReady()
                                    val options = call.argument<Map<String, Any?>>("options")
                                        ?: emptyMap()
                                    downloader.start(
                                        requestId,
                                        url,
                                        Downloader.Options(
                                            maxHeight = (options["maxHeight"] as? Number)
                                                ?.toInt() ?: 0,
                                            audioOnly = options["audioOnly"] as? Boolean
                                                ?: false,
                                            alternate = options["alternate"] as? Boolean
                                                ?: false,
                                        ),
                                    )
                                    mainHandler.post { result.success(null) }
                                } catch (e: Exception) {
                                    mainHandler.post {
                                        result.error(
                                            "ENGINE",
                                            e.message ?: "Couldn't start the downloader.",
                                            e.stackTraceToString().takeLast(1000),
                                        )
                                    }
                                }
                            }
                        }
                    }

                    "cancel" -> {
                        downloader.cancel()
                        result.success(null)
                    }

                    "shareWhatsApp" -> {
                        val path = call.argument<String>("path")
                        if (path == null) {
                            result.error("BAD_ARGS", "Missing file path.", null)
                        } else {
                            result.success(shareWhatsApp(path))
                        }
                    }

                    "shareStatus" -> {
                        val path = call.argument<String>("path")
                        if (path == null) {
                            result.error("BAD_ARGS", "Missing file path.", null)
                        } else {
                            result.success(shareStatus(path))
                        }
                    }

                    "shareSystem" -> {
                        val path = call.argument<String>("path")
                        if (path == null) {
                            result.error("BAD_ARGS", "Missing file path.", null)
                        } else {
                            result.success(shareSystem(path))
                        }
                    }

                    "shareText" -> {
                        val text = call.argument<String>("text")
                        if (text.isNullOrBlank()) {
                            result.error("BAD_ARGS", "Missing text.", null)
                        } else {
                            result.success(shareText(text))
                        }
                    }

                    "saveToGallery" -> {
                        val path = call.argument<String>("path")
                        if (path == null) {
                            result.error("BAD_ARGS", "Missing file path.", null)
                        } else {
                            io.execute {
                                val ok = runCatching {
                                    saveMediaToGallery(
                                        File(path),
                                        File(path).nameWithoutExtension,
                                        File(path).extension.equals("mp3", true),
                                    )["ok"] == true
                                }.getOrDefault(false)
                                mainHandler.post { result.success(ok) }
                            }
                        }
                    }

                    "probe" -> {
                        val url = call.argument<String>("url")
                        if (url.isNullOrBlank()) {
                            result.error("BAD_ARGS", "A link is required.", null)
                        } else {
                            io.execute {
                                try {
                                    ensureEngineReady()
                                    val probe = downloader.probe(url)
                                    mainHandler.post {
                                        result.success(
                                            mapOf(
                                                "title" to probe.title,
                                                "durationMs" to probe.durationMs,
                                                "thumbnailUrl" to probe.thumbnailUrl,
                                                "options" to probe.options.map { it.toMap() },
                                            )
                                        )
                                    }
                                } catch (e: Exception) {
                                    mainHandler.post {
                                        result.error(
                                            "PROBE",
                                            e.message ?: "Couldn't read this link.",
                                            null,
                                        )
                                    }
                                }
                            }
                        }
                    }

                    "diagnose" -> {
                        val url = call.argument<String>("url")
                        if (url.isNullOrBlank()) {
                            result.error("BAD_ARGS", "A link is required.", null)
                        } else {
                            io.execute {
                                val log = runCatching { downloader.diagnose(url) }
                                    .getOrElse { it.message ?: it.toString() }
                                mainHandler.post { result.success(log) }
                            }
                        }
                    }

                    "isOnWifi" -> result.success(isOnWifi())

                    "shareWhatsAppUri" -> {
                        val uri = call.argument<String>("uri")
                        val mime = call.argument<String>("mime") ?: "video/mp4"
                        if (uri.isNullOrBlank()) {
                            result.error("BAD_ARGS", "Missing file URI.", null)
                        } else {
                            result.success(shareWhatsAppUri(Uri.parse(uri), mime))
                        }
                    }

                    "shareStatusUri" -> {
                        val uri = call.argument<String>("uri")
                        val mime = call.argument<String>("mime") ?: "video/mp4"
                        if (uri.isNullOrBlank()) {
                            result.error("BAD_ARGS", "Missing file URI.", null)
                        } else {
                            result.success(shareStatusUri(Uri.parse(uri), mime))
                        }
                    }

                    "shareSystemUri" -> {
                        val uri = call.argument<String>("uri")
                        val mime = call.argument<String>("mime") ?: "video/mp4"
                        if (uri.isNullOrBlank()) {
                            result.error("BAD_ARGS", "Missing file URI.", null)
                        } else {
                            result.success(shareSystemUri(Uri.parse(uri), mime))
                        }
                    }

                    "openUri" -> {
                        val uri = call.argument<String>("uri")
                        val mime = call.argument<String>("mime") ?: "video/mp4"
                        if (uri.isNullOrBlank()) {
                            result.error("BAD_ARGS", "Missing file URI.", null)
                        } else {
                            result.success(openUri(Uri.parse(uri), mime))
                        }
                    }

                    "deleteUri" -> {
                        val uri = call.argument<String>("uri")
                        val path = call.argument<String>("path")
                        if (uri.isNullOrBlank() && path.isNullOrBlank()) {
                            result.error("BAD_ARGS", "Missing file.", null)
                        } else {
                            io.execute {
                                val ok = deleteMedia(uri, path)
                                mainHandler.post { result.success(ok) }
                            }
                        }
                    }

                    "closeApp" -> {
                        result.success(null)
                        finish()
                    }

                    "setScreenOn" -> {
                        val on = call.argument<Boolean>("on") ?: false
                        setScreenOn(on)
                        result.success(null)
                    }

                    "updateEngine" -> updateEngine(result)

                    "engineVersion" -> result.success(
                        runCatching {
                            YoutubeDL.versionName(applicationContext)
                        }.getOrNull() ?: "Bundled"
                    )

                    "hasCookies" -> {
                        val file = cookiesFile()
                        result.success(file.exists() && file.length() > 0L)
                    }

                    "setCookies" -> {
                        val text = call.argument<String>("text")
                        io.execute {
                            val ok = runCatching {
                                val file = cookiesFile()
                                if (text.isNullOrBlank()) {
                                    if (file.exists()) file.delete()
                                } else {
                                    file.parentFile?.mkdirs()
                                    file.writeText(formatCookies(text))
                                }
                                true
                            }.getOrDefault(false)
                            mainHandler.post { result.success(ok) }
                        }
                    }

                    "getPref" -> {
                        val key = call.argument<String>("key")
                        if (key == null) {
                            result.error("BAD_ARGS", "Missing key.", null)
                        } else {
                            result.success(
                                getSharedPreferences(PREFS, MODE_PRIVATE).getString(key, null)
                            )
                        }
                    }

                    "setPref" -> {
                        val key = call.argument<String>("key")
                        val value = call.argument<String>("value")
                        if (key == null) {
                            result.error("BAD_ARGS", "Missing key.", null)
                        } else {
                            getSharedPreferences(PREFS, MODE_PRIVATE)
                                .edit()
                                .putString(key, value)
                                .apply()
                            result.success(true)
                        }
                    }

                    else -> result.notImplemented()
                }
            }

        EventChannel(flutterEngine.dartExecutor.binaryMessenger, EVENT_CHANNEL)
            .setStreamHandler(object : EventChannel.StreamHandler {
                override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                    eventSink = events
                    flutterStarted = true
                    while (pendingEvents.isNotEmpty()) {
                        events?.success(pendingEvents.removeFirst())
                    }
                }

                override fun onCancel(arguments: Any?) {
                    eventSink = null
                }
            })
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        handleShareIntent(intent)
    }

    override fun onDestroy() {
        downloader.cancel()
        io.shutdown()
        super.onDestroy()
    }

    // ---------------------------------------------------------------------
    // Shared link handling
    // ---------------------------------------------------------------------

    private fun handleShareIntent(intent: Intent?) {
        if (intent?.action != Intent.ACTION_SEND) return

        val text = intent.getStringExtra(Intent.EXTRA_TEXT)
            ?: intent.getCharSequenceExtra(Intent.EXTRA_TEXT)?.toString()
            ?: intent.getStringExtra(Intent.EXTRA_SUBJECT)
            ?: intent.getCharSequenceExtra(Intent.EXTRA_SUBJECT)?.toString()
            ?: intent.getStringExtra(Intent.EXTRA_HTML_TEXT)

        val url = extractUrl(text)
        if (url != null) {
            if (!flutterStarted) {
                pendingShare = url
            } else {
                emitEvent(mapOf("type" to "share", "url" to url))
            }
        } else {
            if (!flutterStarted) {
                pendingShareError = "no_link"
            } else {
                emitEvent(mapOf("type" to "share", "error" to "no_link"))
            }
        }
    }

    private fun extractUrl(text: String?): String? {
        if (text.isNullOrBlank()) return null

        val direct = Regex("""https?://[^\s<>"']+""", RegexOption.IGNORE_CASE)
            .find(text)
            ?.value

        val found = direct ?: Regex(
            """(?:https?://)?(?:www\.|m\.|web\.)?(?:instagram\.com|instagr\.am|ig\.me|facebook\.com|fb\.watch|fb\.com|youtube\.com|youtu\.be|youtube-nocookie\.com|tiktok\.com|vm\.tiktok\.com|twitter\.com|x\.com|threads\.net)/[^\s<>"']+""",
            RegexOption.IGNORE_CASE,
        ).find(text)?.value?.let { if (it.startsWith("http", ignoreCase = true)) it else "https://$it" }

        val trimmed = found
            ?.trim()
            ?.trimEnd('.', ',', ')', ']', '"', '\'', '>', ';', '!')

        return trimmed?.let { normalizeSocialUrl(it) }
    }

    private fun normalizeSocialUrl(url: String): String {
        // 1. Instagram share links (e.g. /share/reel/ID -> /reel/ID/)
        val instaShare = Regex("""(?:https?://)?(?:www\.)?instagram\.com/share/(reel|reels|p|tv)/([^/?#&]+)""", RegexOption.IGNORE_CASE)
            .find(url)
        if (instaShare != null) {
            val type = instaShare.groupValues[1].let { if (it.equals("reels", ignoreCase = true)) "reel" else it }
            val id = instaShare.groupValues[2]
            return "https://www.instagram.com/$type/$id/"
        }

        // 2. Facebook direct digit links (canonical numeric IDs)
        val fbShareReel = Regex("""(?:https?://)?(?:www\.|m\.)?facebook\.com/share/r/([^/?#&]+)""", RegexOption.IGNORE_CASE)
            .find(url)
        if (fbShareReel != null && fbShareReel.groupValues[1].all { it.isDigit() }) {
            val id = fbShareReel.groupValues[1]
            return "https://www.facebook.com/reel/$id/"
        }

        val fbShareVideo = Regex("""(?:https?://)?(?:www\.|m\.)?facebook\.com/share/v/([^/?#&]+)""", RegexOption.IGNORE_CASE)
            .find(url)
        if (fbShareVideo != null && fbShareVideo.groupValues[1].all { it.isDigit() }) {
            val id = fbShareVideo.groupValues[1]
            return "https://www.facebook.com/watch/?v=$id"
        }

        // 3. Facebook mobile share links (e.g. /share/r/TOKEN) or fb.watch shortlinks
        if (url.contains("fb.watch", ignoreCase = true) ||
            url.contains("facebook.com/share", ignoreCase = true)
        ) {
            val resolved = resolveFacebookUrl(url)
            if (resolved != url) {
                return normalizeSocialUrl(resolved)
            }
        }

        return url
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

    private fun emitEvent(event: Map<String, Any?>) {
        mainHandler.post {
            val type = event["type"]
            if (type == "done" || type == "error" || type == "cancelled") {
                setScreenOn(false)
            }
            val sink = eventSink
            if (sink != null) {
                try {
                    sink.success(event)
                } catch (_: Exception) {
                    pendingEvents.addLast(event)
                }
            } else {
                pendingEvents.addLast(event)
            }
        }
    }

    // ---------------------------------------------------------------------
    // Engine
    // ---------------------------------------------------------------------

    @Synchronized
    private fun ensureEngineReady() {
        if (engineReady) return
        FFmpeg.init(applicationContext)
        YoutubeDL.init(applicationContext)

        // 1. Force modern yt-dlp binary from res/raw/ytdlp if outdated
        runCatching {
            val ytdlpDir = File(applicationContext.noBackupFilesDir, "youtubedl-android/yt-dlp")
            val ytdlpTarget = File(ytdlpDir, "yt-dlp")
            val rawRes = applicationContext.resources.openRawResource(
                com.yausername.youtubedl_android.R.raw.ytdlp
            )
            rawRes.use { input ->
                val bundledBytes = input.readBytes()
                val ytdlPrefs = applicationContext.getSharedPreferences("youtubedl-android", MODE_PRIVATE)
                val currentVer = ytdlPrefs.getString("dlpVersionName", null)
                val isOutdated = currentVer.isNullOrBlank() ||
                    currentVer.startsWith("2025") ||
                    currentVer == "Bundled" ||
                    ytdlpTarget.length() == 3170726L ||
                    !ytdlpTarget.exists()
                if (isOutdated) {
                    ytdlpDir.mkdirs()
                    ytdlpTarget.writeBytes(bundledBytes)
                    ytdlpTarget.setExecutable(true)
                    ytdlPrefs.edit().putString("dlpVersionName", "2026.10.21").apply()
                }
            }
        }

        // 2. Fix all native library dependencies (libc++_shared.so, libexpat.so.1, libcrypto.so.3, etc.)
        NativeLibraryHelper.fixDependencies(applicationContext)

        engineReady = true
    }

    private fun ensureEngine(result: MethodChannel.Result) {
        io.execute {
            try {
                ensureEngineReady()
                mainHandler.post {
                    val version = runCatching {
                        YoutubeDL.versionName(applicationContext)
                    }.getOrNull() ?: "Bundled"
                    result.success(
                        mapOf(
                            "version" to version,
                            "cookies" to cookiesFile().let { it.exists() && it.length() > 0L },
                        )
                    )
                }
            } catch (e: Exception) {
                mainHandler.post {
                    result.error(
                        "ENGINE",
                        e.message ?: "Couldn't start the downloader.",
                        e.stackTraceToString().takeLast(1200),
                    )
                }
            }
        }
    }

    private fun updateEngine(result: MethodChannel.Result) {
        if (downloader.isBusy()) {
            result.error("BUSY", "Finish the current download first.", null)
            return
        }
        io.execute {
            try {
                val channel = if (
                    getSharedPreferences(PREFS, MODE_PRIVATE)
                        .getString("engine_channel", "nightly") == "stable"
                ) {
                    YoutubeDL.UpdateChannel.STABLE
                } else {
                    YoutubeDL.UpdateChannel.NIGHTLY
                }
                val status = YoutubeDL.updateYoutubeDL(
                    applicationContext,
                    channel,
                )
                val version = runCatching {
                    YoutubeDL.versionName(applicationContext)
                }.getOrNull() ?: ""
                mainHandler.post {
                    result.success(
                        mapOf(
                            "status" to (status?.name ?: "DONE"),
                            "version" to version,
                        )
                    )
                }
            } catch (e: Exception) {
                mainHandler.post {
                    result.error(
                        "UPDATE",
                        e.message ?: "Couldn't update the downloader.",
                        e.stackTraceToString().takeLast(1200),
                    )
                }
            }
        }
    }

    // ---------------------------------------------------------------------
    // Gallery
    // ---------------------------------------------------------------------

    private fun saveVideoToGallery(file: File): Boolean {
        return saveMediaToGallery(file, file.nameWithoutExtension, false)["ok"] == true
    }

    /**
     * Copies the finished file into the Gallery (or Music, for audio-only) with
     * the video's own title, and returns the content URI so the app can open,
     * re-share, and delete it later.
     */
    private fun saveMediaToGallery(
        file: File,
        rawTitle: String,
        audio: Boolean,
    ): Map<String, Any?> {
        if (!file.exists() || file.length() == 0L) return mapOf("ok" to false)

        val extension = if (audio) "mp3" else "mp4"
        val name = "${niceFileName(rawTitle)}.$extension"
        val mime = if (audio) "audio/mpeg" else "video/mp4"

        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.Q) {
            if (ContextCompat.checkSelfPermission(
                    this,
                    Manifest.permission.WRITE_EXTERNAL_STORAGE,
                ) != PackageManager.PERMISSION_GRANTED
            ) {
                mainHandler.post {
                    requestPermissions(
                        arrayOf(Manifest.permission.WRITE_EXTERNAL_STORAGE),
                        STORAGE_REQUEST,
                    )
                }
                return mapOf("ok" to false)
            }
            val base = if (audio) Environment.DIRECTORY_MUSIC else Environment.DIRECTORY_MOVIES
            return runCatching {
                val directory = File(
                    Environment.getExternalStoragePublicDirectory(base),
                    "Save & Send",
                )
                if (!directory.exists() && !directory.mkdirs()) return mapOf("ok" to false)
                var target = File(directory, name)
                var counter = 2
                while (target.exists()) {
                    target = File(directory, "${name.substringBeforeLast('.')} ($counter).$extension")
                    counter += 1
                }
                file.copyTo(target, overwrite = true)
                MediaScannerConnection.scanFile(
                    this,
                    arrayOf(target.absolutePath),
                    arrayOf(mime),
                    null,
                )
                mapOf(
                    "ok" to true,
                    "uri" to fileUri(target).toString(),
                    "path" to target.absolutePath,
                )
            }.getOrDefault(mapOf("ok" to false))
        }

        val collection = if (audio) {
            MediaStore.Audio.Media.getContentUri(MediaStore.VOLUME_EXTERNAL_PRIMARY)
        } else {
            MediaStore.Video.Media.getContentUri(MediaStore.VOLUME_EXTERNAL_PRIMARY)
        }
        val values = ContentValues().apply {
            put(MediaStore.MediaColumns.DISPLAY_NAME, name)
            put(MediaStore.MediaColumns.MIME_TYPE, mime)
            put(MediaStore.MediaColumns.DATE_ADDED, System.currentTimeMillis() / 1000)
            put(
                MediaStore.MediaColumns.RELATIVE_PATH,
                if (audio) {
                    "${Environment.DIRECTORY_MUSIC}/Save & Send"
                } else {
                    "${Environment.DIRECTORY_MOVIES}/Save & Send"
                },
            )
            put(MediaStore.MediaColumns.IS_PENDING, 1)
        }

        val uri = contentResolver.insert(collection, values)
            ?: return mapOf("ok" to false)
        return try {
            contentResolver.openOutputStream(uri)?.use { output ->
                file.inputStream().use { input -> input.copyTo(output) }
            } ?: run {
                contentResolver.delete(uri, null, null)
                return mapOf("ok" to false)
            }
            values.clear()
            values.put(MediaStore.MediaColumns.IS_PENDING, 0)
            contentResolver.update(uri, values, null, null)
            mapOf("ok" to true, "uri" to uri.toString(), "path" to null)
        } catch (_: Exception) {
            runCatching { contentResolver.delete(uri, null, null) }
            mapOf("ok" to false)
        }
    }

    private fun niceFileName(raw: String): String {
        val cleaned = raw
            .replace(Regex("[\\\\/:*?\"<>|\\u0000-\\u001F]"), " ")
            .replace(Regex("\\s+"), " ")
            .trim()
            .trim('.', ' ')
            .take(80)
            .trim()
        return cleaned.ifBlank { "Save & Send" }
    }

    private fun isOnWifi(): Boolean {
        val manager = getSystemService(ConnectivityManager::class.java) ?: return false
        val network = manager.activeNetwork ?: return false
        val capabilities = manager.getNetworkCapabilities(network) ?: return false
        return capabilities.hasTransport(NetworkCapabilities.TRANSPORT_WIFI) ||
            capabilities.hasTransport(NetworkCapabilities.TRANSPORT_ETHERNET)
    }

    // ---------------------------------------------------------------------
    // Sharing
    // ---------------------------------------------------------------------

    private fun shareWhatsApp(path: String): String {
        val file = File(path)
        if (!file.exists()) return "missing"
        return shareWhatsAppUri(fileUri(file), mimeFor(file))
    }

    private fun shareStatus(path: String): String {
        val file = File(path)
        if (!file.exists()) return "missing"
        return shareStatusUri(fileUri(file), mimeFor(file))
    }

    private fun shareSystem(path: String): String {
        val file = File(path)
        if (!file.exists()) return "missing"
        return shareSystemUri(fileUri(file), mimeFor(file))
    }

    private fun shareWhatsAppUri(uri: Uri, mime: String): String {
        val pkg = whatsAppPackage() ?: return "not_installed"
        return try {
            grantUriPermission(pkg, uri, Intent.FLAG_GRANT_READ_URI_PERMISSION)
            val intent = Intent(Intent.ACTION_SEND).apply {
                type = mime
                setPackage(pkg)
                putExtra(Intent.EXTRA_STREAM, uri)
                clipData = ClipData.newUri(contentResolver, "media", uri)
                addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
            }
            startActivity(intent)
            "ok"
        } catch (_: Exception) {
            "failed"
        }
    }

    private fun shareStatusUri(uri: Uri, mime: String): String {
        val pkg = whatsAppPackage() ?: return "not_installed"
        return try {
            grantUriPermission(pkg, uri, Intent.FLAG_GRANT_READ_URI_PERMISSION)
            val intent = Intent(Intent.ACTION_VIEW).apply {
                data = Uri.parse("https://wa.me/status")
                setPackage(pkg)
                putExtra("share_type", "SHARE_TO_STATUS")
                putExtra("source_app_package_name", packageName)
                putExtra(Intent.EXTRA_STREAM, uri)
                clipData = ClipData.newUri(contentResolver, "media", uri)
                addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                addFlags(Intent.FLAG_GRANT_PREFIX_URI_PERMISSION)
            }

            @Suppress("DEPRECATION")
            startActivityForResult(intent, STATUS_REQUEST)
            "ok"
        } catch (_: Exception) {
            // Older WhatsApp builds don't have the Status deep link. The
            // contact picker is the next best thing.
            shareWhatsAppUri(uri, mime).let { if (it == "ok") "chat" else it }
        }
    }

    private fun shareSystemUri(uri: Uri, mime: String): String {
        return try {
            val intent = Intent(Intent.ACTION_SEND).apply {
                type = mime
                putExtra(Intent.EXTRA_STREAM, uri)
                clipData = ClipData.newUri(contentResolver, "media", uri)
                addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
            }
            startActivity(Intent.createChooser(intent, "Share"))
            "ok"
        } catch (_: Exception) {
            "failed"
        }
    }

    private fun openUri(uri: Uri, mime: String): Boolean {
        return try {
            startActivity(
                Intent(Intent.ACTION_VIEW).apply {
                    setDataAndType(uri, mime)
                    addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                },
            )
            true
        } catch (_: Exception) {
            false
        }
    }

    private fun deleteMedia(uri: String?, path: String?): Boolean {
        return runCatching {
            if (!path.isNullOrBlank()) {
                val file = File(path)
                val deleted = !file.exists() || file.delete()
                if (deleted) {
                    MediaScannerConnection.scanFile(this, arrayOf(path), null, null)
                }
                deleted
            } else if (!uri.isNullOrBlank()) {
                contentResolver.delete(Uri.parse(uri), null, null) > 0
            } else {
                false
            }
        }.getOrDefault(false)
    }

    private fun mimeFor(file: File): String {
        return when (file.extension.lowercase()) {
            "mp3" -> "audio/mpeg"
            "m4a" -> "audio/mp4"
            else -> "video/mp4"
        }
    }

    private fun shareText(text: String): String {
        val intent = Intent(Intent.ACTION_SEND).apply {
            type = "text/plain"
            putExtra(Intent.EXTRA_TEXT, text)
        }
        return try {
            startActivity(Intent.createChooser(intent, "Share link"))
            "ok"
        } catch (_: Exception) {
            "failed"
        }
    }

    private fun fileUri(file: File): Uri {
        return FileProvider.getUriForFile(
            this,
            "$packageName.fileprovider",
            file,
        )
    }

    private fun whatsAppPackage(): String? {
        return when {
            isPackageInstalled("com.whatsapp") -> "com.whatsapp"
            isPackageInstalled("com.whatsapp.w4b") -> "com.whatsapp.w4b"
            else -> null
        }
    }

    private fun isPackageInstalled(pkg: String): Boolean {
        return runCatching {
            packageManager.getPackageInfo(pkg, 0)
            true
        }.getOrDefault(false)
    }

    private fun setScreenOn(on: Boolean) {
        if (on) {
            window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
        } else {
            window.clearFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
        }
    }

    private fun cookiesFile(): File = File(filesDir, "cookies.txt")

    private fun formatCookies(raw: String): String {
        val trimmed = raw.trim()
        if (trimmed.startsWith("# Netscape") || trimmed.contains("\t")) {
            return trimmed
        }
        val lines = StringBuilder()
        lines.appendLine("# Netscape HTTP Cookie File")
        lines.appendLine("# Converted by Save & Send")

        val cleaned = if (trimmed.startsWith("Cookie:", ignoreCase = true)) {
            trimmed.substringAfter(":").trim()
        } else {
            trimmed
        }

        val pairs = cleaned.split(Regex("[;\n\r]+"))
        for (pair in pairs) {
            val part = pair.trim()
            if (part.isEmpty() || !part.contains("=")) continue
            val key = part.substringBefore("=").trim()
            val value = part.substringAfter("=").trim()
            if (key.isNotEmpty() && value.isNotEmpty()) {
                lines.appendLine(".instagram.com\tTRUE\t/\tTRUE\t2147483647\t$key\t$value")
                lines.appendLine(".facebook.com\tTRUE\t/\tTRUE\t2147483647\t$key\t$value")
                lines.appendLine(".youtube.com\tTRUE\t/\tTRUE\t2147483647\t$key\t$value")
            }
        }
        return lines.toString()
    }
}
