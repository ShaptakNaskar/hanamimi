package com.hanamimi.app

import android.content.ContentUris
import android.content.Context
import android.graphics.Bitmap
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.provider.MediaStore
import android.util.Size
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.FileOutputStream
import java.util.concurrent.Executors

/**
 * Scans MediaStore for audio files and extracts album art thumbnails.
 * Replaces the abandoned on_audio_query plugin (no AGP 8 support).
 */
class MediaStoreChannel(private val context: Context) {

    // MethodChannel handlers run on the main thread; the scan and the
    // per-album thumbnail decode/compress are far too slow for it
    // (visible freezes/ANRs on large libraries), so do the work here
    // and post only the reply back.
    private val executor = Executors.newSingleThreadExecutor()
    private val mainHandler = Handler(Looper.getMainLooper())

    fun handle(call: io.flutter.plugin.common.MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "queryTracks" -> runAsync(result) { queryTracks() }
            "getAlbumArt" -> {
                val albumId = call.argument<Number>("albumId")!!.toLong()
                runAsync(result) { getAlbumArt(albumId) }
            }
            else -> result.notImplemented()
        }
    }

    private fun <T> runAsync(result: MethodChannel.Result, block: () -> T) {
        executor.execute {
            try {
                val value = block()
                mainHandler.post { result.success(value) }
            } catch (e: Exception) {
                mainHandler.post { result.error("mediastore", e.message, null) }
            }
        }
    }

    private fun queryTracks(): List<Map<String, Any?>> {
        val tracks = mutableListOf<Map<String, Any?>>()
        val projection = arrayOf(
            MediaStore.Audio.Media._ID,
            MediaStore.Audio.Media.TITLE,
            MediaStore.Audio.Media.ARTIST,
            MediaStore.Audio.Media.ALBUM,
            MediaStore.Audio.Media.ALBUM_ID,
            MediaStore.Audio.Media.DURATION,
            MediaStore.Audio.Media.DATA,
            MediaStore.Audio.Media.TRACK,
            MediaStore.Audio.Media.DATE_ADDED,
        )
        val selection = "${MediaStore.Audio.Media.IS_MUSIC} != 0"
        context.contentResolver.query(
            MediaStore.Audio.Media.EXTERNAL_CONTENT_URI,
            projection, selection, null,
            "${MediaStore.Audio.Media.TITLE} COLLATE NOCASE ASC",
        )?.use { cursor ->
            val id = cursor.getColumnIndexOrThrow(MediaStore.Audio.Media._ID)
            val title = cursor.getColumnIndexOrThrow(MediaStore.Audio.Media.TITLE)
            val artist = cursor.getColumnIndexOrThrow(MediaStore.Audio.Media.ARTIST)
            val album = cursor.getColumnIndexOrThrow(MediaStore.Audio.Media.ALBUM)
            val albumId = cursor.getColumnIndexOrThrow(MediaStore.Audio.Media.ALBUM_ID)
            val duration = cursor.getColumnIndexOrThrow(MediaStore.Audio.Media.DURATION)
            val data = cursor.getColumnIndexOrThrow(MediaStore.Audio.Media.DATA)
            val trackNo = cursor.getColumnIndexOrThrow(MediaStore.Audio.Media.TRACK)
            while (cursor.moveToNext()) {
                tracks.add(
                    mapOf(
                        "mediaId" to cursor.getLong(id),
                        "title" to cursor.getString(title),
                        "artist" to cursor.getString(artist),
                        "album" to cursor.getString(album),
                        "albumId" to cursor.getLong(albumId),
                        "durationMs" to cursor.getLong(duration),
                        "filePath" to cursor.getString(data),
                        "trackNumber" to cursor.getInt(trackNo),
                    )
                )
            }
        }
        return tracks
    }

    /** Saves a 512px album art thumbnail to the cache dir; returns its path, or null. */
    private fun getAlbumArt(albumId: Long): String? {
        val artDir = File(context.cacheDir, "album_art").apply { mkdirs() }
        val outFile = File(artDir, "$albumId.jpg")
        if (outFile.exists()) return outFile.absolutePath

        val bitmap: Bitmap = try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                val uri = ContentUris.withAppendedId(
                    MediaStore.Audio.Albums.EXTERNAL_CONTENT_URI, albumId
                )
                context.contentResolver.loadThumbnail(uri, Size(512, 512), null)
            } else {
                return null
            }
        } catch (e: Exception) {
            return null
        }

        FileOutputStream(outFile).use {
            bitmap.compress(Bitmap.CompressFormat.JPEG, 90, it)
        }
        return outFile.absolutePath
    }
}
