package com.personal.save_and_send

import android.content.Context
import android.util.Log
import java.io.File

object NativeLibraryHelper {
    private const val TAG = "NativeLibraryHelper"

    @Synchronized
    fun fixDependencies(context: Context) {
        runCatching {
            val noBackup = context.noBackupFilesDir
            val ffmpegLibs = File(noBackup, "youtubedl-android/packages/ffmpeg/usr/lib")
            val pythonLibs = File(noBackup, "youtubedl-android/packages/python/usr/lib")
            val nativeLibs = File(context.applicationInfo.nativeLibraryDir)

            if (!ffmpegLibs.exists()) {
                ffmpegLibs.mkdirs()
            }

            // 1. Ensure libc++_shared.so is copied from nativeLibraryDir into packages/ffmpeg/usr/lib and packages/python/usr/lib
            val sourceLibcxx = File(nativeLibs, "libc++_shared.so")
            if (sourceLibcxx.exists()) {
                val targetFfLibcxx = File(ffmpegLibs, "libc++_shared.so")
                if (!targetFfLibcxx.exists() || targetFfLibcxx.length() != sourceLibcxx.length()) {
                    sourceLibcxx.copyTo(targetFfLibcxx, overwrite = true)
                    targetFfLibcxx.setReadable(true, false)
                    targetFfLibcxx.setExecutable(true, false)
                }
                if (pythonLibs.exists()) {
                    val targetPyLibcxx = File(pythonLibs, "libc++_shared.so")
                    if (!targetPyLibcxx.exists() || targetPyLibcxx.length() != sourceLibcxx.length()) {
                        sourceLibcxx.copyTo(targetPyLibcxx, overwrite = true)
                        targetPyLibcxx.setReadable(true, false)
                        targetPyLibcxx.setExecutable(true, false)
                    }
                }
            }

            // 2. Resolve all .so dependencies from pythonLibs and copy real binaries into ffmpegLibs
            // Specifically: libexpat.so.1 (needed by libfontconfig.so),
            // libcrypto.so.3 (needed by libsrt.so/libssh.so),
            // libandroid-support.so (needed by libunistring.so),
            // libandroid-posix-semaphore.so (needed by libx265.so).
            if (pythonLibs.exists() && pythonLibs.isDirectory) {
                pythonLibs.listFiles()?.forEach { file ->
                    val name = file.name
                    if (name.endsWith(".so") || name.contains(".so.")) {
                        val realBinary = resolveRealBinary(file, pythonLibs)
                        if (realBinary != null && realBinary.exists() && realBinary.length() > 0) {
                            // If the file in pythonLibs was a symlink or short text file pointing to a real binary,
                            // repair pythonLibs itself so Python/yt-dlp can also load it directly
                            if (file.length() < realBinary.length()) {
                                runCatching {
                                    file.delete()
                                    realBinary.copyTo(file, overwrite = true)
                                    file.setReadable(true, false)
                                    file.setExecutable(true, false)
                                }
                            }

                            // Copy the real binary into ffmpegLibs so the Android linker immediately
                            // finds it in libfontconfig.so's own directory
                            val dest = File(ffmpegLibs, name)
                            if (!dest.exists() || dest.length() != realBinary.length()) {
                                realBinary.copyTo(dest, overwrite = true)
                                dest.setReadable(true, false)
                                dest.setExecutable(true, false)
                            }
                        }
                    }
                }
            }

            // Ensure all binaries in ffmpegLibs have proper permissions
            ffmpegLibs.listFiles()?.forEach { lib ->
                if (lib.name.endsWith(".so") || lib.name.contains(".so.")) {
                    lib.setReadable(true, false)
                    lib.setExecutable(true, false)
                }
            }
        }.onFailure { e ->
            Log.w(TAG, "Failed to fix native library dependencies", e)
        }
    }

    private fun resolveRealBinary(file: File, searchDir: File): File? {
        return runCatching {
            // Check canonical file first
            val canon = file.canonicalFile
            if (canon.exists() && canon.isFile && canon.length() >= 512L) {
                return@runCatching canon
            }
            // Check if it's a symlink stored as a plain text path (< 256 bytes)
            if (file.exists() && file.isFile && file.length() in 1..256) {
                val targetName = file.readText().trim()
                if (targetName.isNotBlank()) {
                    val target = File(searchDir, targetName)
                    if (target.exists() && target.isFile && target.length() >= 512L) {
                        return@runCatching target
                    }
                    val deep = target.canonicalFile
                    if (deep.exists() && deep.isFile && deep.length() >= 512L) {
                        return@runCatching deep
                    }
                }
            }
            if (file.exists() && file.isFile && file.length() > 0) file else null
        }.getOrNull()
    }

    fun getLdLibraryPath(context: Context): String {
        val noBackup = context.noBackupFilesDir
        val ffmpegLibs = File(noBackup, "youtubedl-android/packages/ffmpeg/usr/lib")
        val pythonLibs = File(noBackup, "youtubedl-android/packages/python/usr/lib")
        val aria2cLibs = File(noBackup, "youtubedl-android/packages/aria2c/usr/lib")
        val nativeLibs = File(context.applicationInfo.nativeLibraryDir)

        val paths = mutableListOf<String>()
        if (ffmpegLibs.exists()) paths += ffmpegLibs.absolutePath
        if (pythonLibs.exists()) paths += pythonLibs.absolutePath
        if (aria2cLibs.exists()) paths += aria2cLibs.absolutePath
        if (nativeLibs.exists()) paths += nativeLibs.absolutePath

        return paths.joinToString(":")
    }
}
