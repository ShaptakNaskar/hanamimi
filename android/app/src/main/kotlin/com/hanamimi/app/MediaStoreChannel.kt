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
                val filePath = call.argument<String>("filePath")
                runAsync(result) { getAlbumArt(albumId, filePath) }
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
                val path = cursor.getString(data)
                tracks.add(
                    mapOf(
                        "mediaId" to cursor.getLong(id),
                        "title" to cursor.getString(title),
                        "artist" to bestArtist(path, cursor.getString(artist)),
                        "album" to cursor.getString(album),
                        "albumId" to cursor.getLong(albumId),
                        "durationMs" to cursor.getLong(duration),
                        "filePath" to path,
                        "trackNumber" to cursor.getInt(trackNo),
                    )
                )
            }
        }
        return tracks
    }

    /**
     * MediaStore (and MediaMetadataRetriever) split a multi-artist tag like
     * "Lane 8;Kasablanca" on ';' and keep only the last part ("Kasablanca"),
     * losing the co-artist. For FLAC we parse the raw Vorbis comment
     * ourselves to recover every artist ("Lane 8, Kasablanca"). Anything
     * else, or on failure, falls back to MediaStore's value.
     */
    private fun bestArtist(path: String?, fallback: String?): String? {
        if (path == null) return fallback
        val artists = try {
            if (path.endsWith(".flac", true)) readFlacArtists(path) else null
        } catch (_: Exception) {
            null
        }
        if (artists.isNullOrEmpty()) return fallback
        return artists.joinToString(", ")
    }

    /**
     * Minimal FLAC VORBIS_COMMENT reader: pulls every ARTIST value.
     * A FLAC is "fLaC" + metadata blocks; block type 4 is the Vorbis
     * comment (little-endian lengths). Multi-artist appears either as
     * repeated ARTIST entries or one entry joined by ';' / NUL.
     */
    private fun readFlacArtists(path: String): List<String>? {
        java.io.RandomAccessFile(path, "r").use { raf ->
            val magic = ByteArray(4)
            if (raf.read(magic) != 4 || String(magic, Charsets.US_ASCII) != "fLaC") {
                return null
            }
            while (true) {
                val header = raf.read()
                if (header < 0) break
                val last = header and 0x80 != 0
                val type = header and 0x7F
                val b1 = raf.read(); val b2 = raf.read(); val b3 = raf.read()
                if (b3 < 0) break
                val len = (b1 shl 16) or (b2 shl 8) or b3
                if (type == 4) { // VORBIS_COMMENT
                    val block = ByteArray(len)
                    if (raf.read(block) != len) return null
                    return parseVorbisArtists(block)
                }
                raf.seek(raf.filePointer + len)
                if (last) break
            }
        }
        return null
    }

    private fun parseVorbisArtists(b: ByteArray): List<String> {
        var p = 0
        fun le32(): Int {
            val v = (b[p].toInt() and 0xFF) or
                ((b[p + 1].toInt() and 0xFF) shl 8) or
                ((b[p + 2].toInt() and 0xFF) shl 16) or
                ((b[p + 3].toInt() and 0xFF) shl 24)
            p += 4
            return v
        }
        val vendorLen = le32(); p += vendorLen // skip vendor string
        val count = le32()
        val out = mutableListOf<String>()
        for (i in 0 until count) {
            if (p + 4 > b.size) break
            val cLen = le32()
            if (cLen < 0 || p + cLen > b.size) break
            val comment = String(b, p, cLen, Charsets.UTF_8)
            p += cLen
            val eq = comment.indexOf('=')
            if (eq <= 0) continue
            if (!comment.substring(0, eq).equals("ARTIST", true)) continue
            // One entry may hold several artists joined by ';' or NUL.
            comment.substring(eq + 1).split(';', '\u0000')
                .map { it.trim() }
                .filter { it.isNotEmpty() }
                .forEach { out.add(it) }
        }
        return out
    }

    /**
     * Saves a 512px album art thumbnail to the cache dir; returns its path,
     * or null. MediaProvider's thumbnailer is tried first but silently fails
     * on some embedded covers, so a file from the album (when given) is also
     * read directly: MediaMetadataRetriever's embedded picture, then — since
     * Android's FLAC extractor has let us down before — the raw FLAC
     * PICTURE block.
     */
    private fun getAlbumArt(albumId: Long, filePath: String?): String? {
        val artDir = File(context.cacheDir, "album_art").apply { mkdirs() }
        val outFile = File(artDir, "$albumId.jpg")
        if (outFile.exists()) return outFile.absolutePath

        var bitmap: Bitmap? = try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                val uri = ContentUris.withAppendedId(
                    MediaStore.Audio.Albums.EXTERNAL_CONTENT_URI, albumId
                )
                context.contentResolver.loadThumbnail(uri, Size(512, 512), null)
            } else {
                null
            }
        } catch (e: Exception) {
            null
        }

        if (bitmap == null && filePath != null) {
            val bytes = embeddedPicture(filePath)
                ?: if (filePath.endsWith(".flac", true)) readFlacPicture(filePath) else null
            if (bytes != null) bitmap = decodeScaled(bytes, 512)
        }
        if (bitmap == null) return null

        FileOutputStream(outFile).use {
            bitmap.compress(Bitmap.CompressFormat.JPEG, 90, it)
        }
        return outFile.absolutePath
    }

    private fun embeddedPicture(path: String): ByteArray? = try {
        val mmr = android.media.MediaMetadataRetriever()
        try {
            mmr.setDataSource(path)
            mmr.embeddedPicture
        } finally {
            mmr.release()
        }
    } catch (_: Exception) {
        null
    }

    /**
     * Raw FLAC PICTURE (block type 6) reader. Layout after the block
     * header, all big-endian: picture type (4), MIME len (4) + string,
     * description len (4) + string, width/height/depth/colors (4 each),
     * data length (4), image data.
     */
    private fun readFlacPicture(path: String): ByteArray? {
        try {
            java.io.RandomAccessFile(path, "r").use { raf ->
                val magic = ByteArray(4)
                if (raf.read(magic) != 4 || String(magic, Charsets.US_ASCII) != "fLaC") {
                    return null
                }
                while (true) {
                    val header = raf.read()
                    if (header < 0) break
                    val last = header and 0x80 != 0
                    val type = header and 0x7F
                    val b1 = raf.read(); val b2 = raf.read(); val b3 = raf.read()
                    if (b3 < 0) break
                    val len = (b1 shl 16) or (b2 shl 8) or b3
                    if (type == 6) {
                        val blockEnd = raf.filePointer + len
                        fun be32(): Int {
                            val b = ByteArray(4)
                            if (raf.read(b) != 4) return -1
                            return ((b[0].toInt() and 0xFF) shl 24) or
                                ((b[1].toInt() and 0xFF) shl 16) or
                                ((b[2].toInt() and 0xFF) shl 8) or
                                (b[3].toInt() and 0xFF)
                        }
                        raf.seek(raf.filePointer + 4) // picture type
                        val mimeLen = be32()
                        if (mimeLen < 0) return null
                        raf.seek(raf.filePointer + mimeLen)
                        val descLen = be32()
                        if (descLen < 0) return null
                        raf.seek(raf.filePointer + descLen + 16) // w/h/depth/colors
                        val dataLen = be32()
                        if (dataLen <= 0 || raf.filePointer + dataLen > blockEnd) return null
                        val data = ByteArray(dataLen)
                        if (raf.read(data) != dataLen) return null
                        return data
                    }
                    raf.seek(raf.filePointer + len)
                    if (last) break
                }
            }
        } catch (_: Exception) {
            return null
        }
        return null
    }

    /** Decodes image bytes downsampled to roughly the target edge. */
    private fun decodeScaled(bytes: ByteArray, target: Int): Bitmap? = try {
        val bounds = android.graphics.BitmapFactory.Options().apply {
            inJustDecodeBounds = true
        }
        android.graphics.BitmapFactory.decodeByteArray(bytes, 0, bytes.size, bounds)
        var sample = 1
        while (bounds.outWidth / (sample * 2) >= target &&
            bounds.outHeight / (sample * 2) >= target) {
            sample *= 2
        }
        val opts = android.graphics.BitmapFactory.Options().apply {
            inSampleSize = sample
        }
        android.graphics.BitmapFactory.decodeByteArray(bytes, 0, bytes.size, opts)
    } catch (_: Exception) {
        null
    }
}
