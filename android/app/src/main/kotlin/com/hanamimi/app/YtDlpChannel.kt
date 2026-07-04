package com.hanamimi.app

import android.content.Context
import android.util.Log
import com.yausername.youtubedl_android.YoutubeDL
import com.yausername.youtubedl_android.YoutubeDLRequest
import com.yausername.youtubedl_android.mapper.VideoFormat
import com.yausername.youtubedl_android.mapper.VideoInfo
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.util.concurrent.Executors

/**
 * Embedded yt-dlp bridge (M28, plus-only). Backs YouTube stream
 * resolution with the bundled Python yt-dlp instead of the pure-Dart
 * youtube_explode — yt-dlp's own interpreter deciphers the `n`
 * parameter, killing the ~1× download throttle that made bulk
 * downloads crawl.
 *
 * We stay on the no-PO-token player clients (`android_vr`,
 * `web_embedded`): those serve audio without a proof-of-origin token,
 * so there's no need for the Node.js/BotGuard companion that ytdlnis
 * uses for the login-gated clients. If YouTube ever gates these too,
 * the fallback to youtube_explode on the Dart side still plays.
 *
 * Method channel "hanamimi/ytdlp":
 *   resolve(id, quality) -> { url, codec, abr, asr, ext, expiresAtMs } | null
 *   update()             -> version string | null
 *   version()            -> version string | null
 */
class YtDlpChannel(private val context: Context) {
    companion object {
        private const val TAG = "YtDlpChannel"

        // No-PO-token clients. android_vr first (its URLs carry no nsig
        // gate at all); web_embedded as a second opinion.
        private const val PLAYER_CLIENTS = "youtube:player_client=android_vr,web_embedded"

        // Fallback stream lifetime when the URL has no ?expire= (~6 h).
        private const val DEFAULT_TTL_SECONDS = 6L * 60 * 60
    }

    // yt-dlp calls spawn Python and block; keep them off the main thread.
    // Single thread also serialises init so it only unpacks once.
    private val io = Executors.newSingleThreadExecutor()

    @Volatile
    private var initialized = false

    fun handle(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "resolve" -> {
                val id = call.argument<String>("id")
                val quality = call.argument<String>("quality") ?: "high"
                if (id == null) {
                    result.success(null)
                    return
                }
                io.execute { resolve(id, quality, result) }
            }
            "update" -> io.execute { update(result) }
            "version" -> io.execute {
                val v = ensureInit().let { ok -> if (ok) safeVersion() else null }
                postSuccess(result, v)
            }
            else -> result.notImplemented()
        }
    }

    /** Unpacks Python + yt-dlp on the first call (~1–2 s). Returns false on failure. */
    private fun ensureInit(): Boolean {
        if (initialized) return true
        return try {
            YoutubeDL.init(context)
            initialized = true
            true
        } catch (e: Throwable) {
            Log.e(TAG, "yt-dlp init failed", e)
            false
        }
    }

    private fun resolve(id: String, quality: String, result: MethodChannel.Result) {
        if (!ensureInit()) {
            postSuccess(result, null)
            return
        }
        try {
            val format =
                if (quality == "low") "bestaudio[abr<=96]/bestaudio/best"
                else "bestaudio/best"
            val request = YoutubeDLRequest("https://www.youtube.com/watch?v=$id").apply {
                addOption("-f", format)
                addOption("--no-playlist")
                addOption("--extractor-args", PLAYER_CLIENTS)
                // Metadata only — never touch the filesystem.
                addOption("--skip-download")
            }
            val info: VideoInfo = YoutubeDL.getInfo(request)
            val url = info.url
            if (url.isNullOrEmpty()) {
                postSuccess(result, null)
                return
            }

            val chosen = selectedFormat(info)
            val expiresAtMs = expiryMillis(url)
            postSuccess(
                result,
                mapOf(
                    "url" to url,
                    "codec" to (chosen?.acodec?.takeIf { it != "none" } ?: info.ext),
                    "abr" to (chosen?.abr?.takeIf { it > 0 }),
                    "asr" to (chosen?.asr?.takeIf { it > 0 }),
                    "ext" to (chosen?.ext ?: info.ext),
                    "expiresAtMs" to expiresAtMs,
                ),
            )
        } catch (e: Throwable) {
            // Extraction broke (YouTube change, geo-block, native crash).
            // Null lets the Dart layer fall back to youtube_explode.
            Log.w(TAG, "yt-dlp resolve failed for $id", e)
            postSuccess(result, null)
        }
    }

    /** The concrete format yt-dlp settled on, matched by format_id. */
    private fun selectedFormat(info: VideoInfo): VideoFormat? {
        val formats = info.formats ?: return null
        val byId = formats.firstOrNull { it.formatId == info.formatId }
        if (byId != null) return byId
        // Fallback: highest-bitrate audio-only format present.
        return formats
            .filter { it.acodec != null && it.acodec != "none" && (it.vcodec == null || it.vcodec == "none") }
            .maxByOrNull { it.abr }
    }

    /** googlevideo URLs carry ?expire=<unix seconds>; conservative default otherwise. */
    private fun expiryMillis(url: String): Long {
        val expire = Regex("[?&]expire=(\\d+)").find(url)?.groupValues?.get(1)?.toLongOrNull()
        val seconds = expire ?: (System.currentTimeMillis() / 1000 + DEFAULT_TTL_SECONDS)
        return seconds * 1000
    }

    private fun update(result: MethodChannel.Result) {
        if (!ensureInit()) {
            postSuccess(result, null)
            return
        }
        try {
            YoutubeDL.updateYoutubeDL(context, YoutubeDL.UpdateChannel.STABLE)
            postSuccess(result, safeVersion())
        } catch (e: Throwable) {
            Log.w(TAG, "yt-dlp update failed", e)
            postSuccess(result, null)
        }
    }

    private fun safeVersion(): String? =
        try {
            YoutubeDL.version(context)
        } catch (_: Throwable) {
            null
        }

    // MethodChannel.Result must be answered on the main thread.
    private val mainHandler = android.os.Handler(android.os.Looper.getMainLooper())

    private fun postSuccess(result: MethodChannel.Result, value: Any?) {
        mainHandler.post { result.success(value) }
    }
}
