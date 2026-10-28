package com.personal.save_and_send

import android.content.Context
import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyProperties
import java.io.File
import java.security.KeyStore
import javax.crypto.Cipher
import javax.crypto.KeyGenerator
import javax.crypto.SecretKey
import javax.crypto.spec.GCMParameterSpec

/**
 * Keeps the pasted cookie jar encrypted at rest with an Android Keystore key.
 *
 * yt-dlp needs a readable Netscape file, so the jar is decrypted into the cache
 * only while a request is running and deleted as soon as it finishes. If the
 * keystore is unavailable, the store falls back to the old plaintext file
 * instead of losing the user's cookies.
 */
object CookieStore {

    private const val ALIAS = "save_and_send_cookies_v1"
    private const val ENCRYPTED = "cookies.enc"
    private const val LEGACY = "cookies.txt"
    private const val VERSION: Byte = 1
    private const val IV_BYTES = 12
    private const val TAG_BITS = 128

    private val lock = Any()
    private var open = 0

    fun has(context: Context): Boolean = synchronized(lock) {
        migrate(context)
        encrypted(context).exists() || legacy(context).exists()
    }

    /** Encrypts [text], or removes the jar when it is null or blank. */
    fun save(context: Context, text: String?) = synchronized(lock) {
        if (text.isNullOrBlank()) {
            removeLocked(context)
            return@synchronized
        }
        migrate(context)
        val wrote = runCatching { writeEncrypted(context, text.toByteArray()) }.isSuccess
        if (wrote) {
            legacy(context).delete()
        } else {
            // Keystore refused: keep the old behaviour rather than losing it.
            legacy(context).writeText(text)
            encrypted(context).delete()
        }
        cache(context).delete()
    }

    fun remove(context: Context) = synchronized(lock) { removeLocked(context) }

    /**
     * Writes a temporary plaintext copy for yt-dlp and returns it. Calls are
     * counted, so nested requests share one file and the last release removes
     * it.
     */
    fun materialize(context: Context): File? = synchronized(lock) {
        migrate(context)
        val cache = cache(context)
        if (cache.exists() && cache.length() > 0L) {
            open += 1
            return@synchronized cache
        }
        val bytes = runCatching { readEncrypted(context) }.getOrNull()
            ?: legacy(context).takeIf { it.exists() && it.length() > 0L }?.readBytes()
            ?: return@synchronized null
        cache.parentFile?.mkdirs()
        cache.writeBytes(bytes)
        open += 1
        cache
    }

    fun release(context: Context) = synchronized(lock) {
        if (open > 0) open -= 1
        if (open == 0) cache(context).delete()
    }

    /** Drops the temporary copy regardless of the counter (app shutdown, clear cache). */
    fun discardCache(context: Context) = synchronized(lock) {
        open = 0
        cache(context).delete()
    }

    fun cacheFile(context: Context): File = cache(context)

    // ---------------------------------------------------------------------

    private fun removeLocked(context: Context) {
        encrypted(context).delete()
        legacy(context).delete()
        cache(context).delete()
        open = 0
    }

    /** Encrypts a cookie file left by an older version, then deletes it. */
    private fun migrate(context: Context) {
        val legacy = legacy(context)
        if (!legacy.exists() || legacy.length() == 0L) return
        val encrypted = encrypted(context)
        if (encrypted.exists() && encrypted.length() > 0L) {
            legacy.delete()
            return
        }
        if (runCatching { writeEncrypted(context, legacy.readBytes()) }.isSuccess) {
            legacy.delete()
        }
    }

    private fun writeEncrypted(context: Context, plain: ByteArray) {
        val cipher = Cipher.getInstance("AES/GCM/NoPadding")
        cipher.init(Cipher.ENCRYPT_MODE, secretKey())
        val iv = cipher.iv
        val body = cipher.doFinal(plain)
        val out = encrypted(context)
        out.parentFile?.mkdirs()
        out.outputStream().use { stream ->
            stream.write(VERSION.toInt())
            stream.write(iv, 0, iv.size)
            stream.write(body)
        }
    }

    private fun readEncrypted(context: Context): ByteArray {
        val raw = encrypted(context).readBytes()
        require(raw.size > 1 + IV_BYTES) { "Cookie jar is empty." }
        require(raw[0] == VERSION) { "Unknown cookie jar version." }
        val iv = raw.copyOfRange(1, 1 + IV_BYTES)
        val body = raw.copyOfRange(1 + IV_BYTES, raw.size)
        val cipher = Cipher.getInstance("AES/GCM/NoPadding")
        cipher.init(
            Cipher.DECRYPT_MODE,
            secretKey(),
            GCMParameterSpec(TAG_BITS, iv),
        )
        return cipher.doFinal(body)
    }

    private fun secretKey(): SecretKey {
        val store = KeyStore.getInstance("AndroidKeyStore").apply { load(null) }
        val existing = store.getEntry(ALIAS, null) as? KeyStore.SecretKeyEntry
        if (existing != null) return existing.secretKey

        val generator = KeyGenerator.getInstance(
            KeyProperties.KEY_ALGORITHM_AES,
            "AndroidKeyStore",
        )
        generator.init(
            KeyGenParameterSpec.Builder(
                ALIAS,
                KeyProperties.PURPOSE_ENCRYPT or KeyProperties.PURPOSE_DECRYPT,
            )
                .setBlockModes(KeyProperties.BLOCK_MODE_GCM)
                .setEncryptionPaddings(KeyProperties.ENCRYPTION_PADDING_NONE)
                .setKeySize(256)
                .build()
        )
        return generator.generateKey()
    }

    private fun encrypted(context: Context) = File(context.filesDir, ENCRYPTED)
    private fun legacy(context: Context) = File(context.filesDir, LEGACY)
    private fun cache(context: Context) = File(context.cacheDir, LEGACY)
}
