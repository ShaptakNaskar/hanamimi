package com.hanamimi.app

import android.content.Context
import android.media.AudioFormat
import android.media.MediaCodec
import android.media.MediaExtractor
import android.media.MediaFormat
import android.net.Uri
import android.os.Handler
import android.os.Looper
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel
import java.io.DataInputStream
import java.io.DataOutputStream
import java.io.File
import java.nio.ByteOrder
import java.util.concurrent.Executors
import java.util.concurrent.atomic.AtomicInteger
import kotlin.math.PI
import kotlin.math.cos
import kotlin.math.min
import kotlin.math.sin
import kotlin.math.sqrt

/**
 * Visualizer band data computed from the audio file itself:
 * MediaExtractor + MediaCodec decode → Hann-windowed 2048-point FFT →
 * 12 log-spaced band amplitudes at 60 frames/second.
 *
 * This replaces android.media.audiofx.Visualizer, which needs the
 * RECORD_AUDIO permission to tap the output mix. Decoding runs many
 * times faster than realtime on a background thread and results are
 * cached per track, so repeat plays stream instantly from disk.
 *
 * Method channel "hanamimi/fft": start(path, key) / cancel.
 * Event channel "hanamimi/fft/frames": maps of
 *   {key, offset (frame index), bands (DoubleArray, frames×14),
 *    stride (14), done}.
 * Each frame is 12 band amplitudes followed by the left and right
 * channel RMS (true VU-meter loudness; equal for mono sources). Values
 * are raw 0..~1; the Dart side applies the perceptual curve, user
 * sensitivity and attack/decay smoothing. Matches DesktopFft exactly —
 * same cache layout, same 'stride' flag.
 */
class FftExtractorChannel(private val context: Context) : EventChannel.StreamHandler {
    companion object {
        const val FRAME_RATE = 60
        const val BANDS = 12
        const val FRAME_FLOATS = BANDS + 2 // + rmsL, rmsR
        private const val WINDOW = 2048
        private const val CHUNK_FRAMES = 120 // ~2s of frames per event
        private const val MAX_CACHE_FILES = 64
    }

    private val executor = Executors.newSingleThreadExecutor()
    private val mainHandler = Handler(Looper.getMainLooper())
    private var events: EventChannel.EventSink? = null

    // Bumping the counter invalidates any older running job.
    private val jobCounter = AtomicInteger()

    fun handle(call: io.flutter.plugin.common.MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "start" -> {
                val path = call.argument<String>("path")!!
                val key = call.argument<String>("key")!!
                val job = jobCounter.incrementAndGet()
                executor.execute { extract(job, path, key) }
                result.success(null)
            }
            "cancel" -> {
                jobCounter.incrementAndGet()
                result.success(null)
            }
            else -> result.notImplemented()
        }
    }

    override fun onListen(arguments: Any?, sink: EventChannel.EventSink?) {
        events = sink
    }

    override fun onCancel(arguments: Any?) {
        events = null
    }

    private fun alive(job: Int) = jobCounter.get() == job

    private fun send(job: Int, key: String, offset: Int, frames: DoubleArray, done: Boolean) {
        mainHandler.post {
            if (alive(job)) {
                events?.success(
                    mapOf(
                        "key" to key, "offset" to offset, "bands" to frames,
                        "stride" to FRAME_FLOATS, "done" to done
                    )
                )
            }
        }
    }

    private fun cacheFile(key: String): File {
        val dir = File(context.cacheDir, "fft").apply { mkdirs() }
        return File(dir, "$key.bin")
    }

    private fun trimCache() {
        val dir = File(context.cacheDir, "fft")
        val files = dir.listFiles() ?: return
        if (files.size <= MAX_CACHE_FILES) return
        files.sortedBy { it.lastModified() }
            .take(files.size - MAX_CACHE_FILES)
            .forEach { it.delete() }
    }

    private fun extract(job: Int, path: String, key: String) {
        try {
            val cached = cacheFile(key)
            if (cached.exists()) {
                streamCached(job, key, cached)
                return
            }
            decodeAndAnalyze(job, path, key, cached)
        } catch (_: Exception) {
            // Unsupported codec / unreadable file — Dart falls back to
            // the synthetic pulse.
            send(job, key, 0, DoubleArray(0), true)
        }
    }

    /** Cache format: [int frameCount][float band…] (big-endian, DataStream). */
    private fun streamCached(job: Int, key: String, file: File) {
        DataInputStream(file.inputStream().buffered()).use { input ->
            val frameCount = input.readInt()
            if (frameCount <= 0) {
                send(job, key, 0, DoubleArray(0), true)
                return
            }
            var offset = 0
            while (offset < frameCount && alive(job)) {
                val n = min(CHUNK_FRAMES * 4, frameCount - offset)
                val chunk = DoubleArray(n * FRAME_FLOATS)
                for (i in chunk.indices) chunk[i] = input.readFloat().toDouble()
                send(job, key, offset, chunk, offset + n >= frameCount)
                offset += n
            }
        }
        file.setLastModified(System.currentTimeMillis())
    }

    private fun decodeAndAnalyze(job: Int, path: String, key: String, cacheOut: File) {
        val extractor = MediaExtractor()
        if (path.startsWith("content://")) {
            extractor.setDataSource(context, Uri.parse(path), null)
        } else {
            extractor.setDataSource(path)
        }

        var trackIndex = -1
        var format: MediaFormat? = null
        for (i in 0 until extractor.trackCount) {
            val f = extractor.getTrackFormat(i)
            if ((f.getString(MediaFormat.KEY_MIME) ?: "").startsWith("audio/")) {
                trackIndex = i
                format = f
                break
            }
        }
        if (trackIndex < 0 || format == null) {
            extractor.release()
            send(job, key, 0, DoubleArray(0), true)
            return
        }
        extractor.selectTrack(trackIndex)

        val codec = MediaCodec.createDecoderByType(format.getString(MediaFormat.KEY_MIME)!!)
        codec.configure(format, null, null, 0)
        codec.start()

        var sampleRate = format.getIntOrDefault(MediaFormat.KEY_SAMPLE_RATE, 44100)
        var channels = format.getIntOrDefault(MediaFormat.KEY_CHANNEL_COUNT, 2)
        var pcmFloat = false
        // Fractional hop: integer division drifts for rates not divisible
        // by 60 (22050 → 367 vs 367.5 ≈ 0.2s/3min visual lead).
        var hop = sampleRate.toDouble() / FRAME_RATE

        val fft = Fft(WINDOW)
        val window = DoubleArray(WINDOW) { 0.5 * (1 - cos(2 * PI * it / (WINDOW - 1))) }
        val ring = FloatArray(WINDOW)
        var written = 0L // total mono samples seen
        var nextFrameAt = hop
        var bandEdges = bandEdgeBins(sampleRate)

        val pending = ArrayList<Double>(CHUNK_FRAMES * FRAME_FLOATS)
        var framesSent = 0
        var frameCount = 0
        // Per-hop channel energy for the VU RMS.
        var sumL2 = 0.0
        var sumR2 = 0.0
        var hopSamples = 0
        val tmpFile = File(cacheOut.parentFile, "${cacheOut.name}.tmp")
        val cache = DataOutputStream(tmpFile.outputStream().buffered())
        cache.writeInt(0) // frame count patched at the end

        fun flushPending(done: Boolean) {
            if (pending.isEmpty() && !done) return
            val chunk = pending.toDoubleArray()
            send(job, key, framesSent, chunk, done)
            framesSent += pending.size / FRAME_FLOATS
            pending.clear()
        }

        fun analyzeFrame() {
            val re = DoubleArray(WINDOW)
            val im = DoubleArray(WINDOW)
            // Oldest→newest out of the ring, zero-padded before start.
            val have = min(written, WINDOW.toLong()).toInt()
            val startPad = WINDOW - have
            for (i in 0 until have) {
                val src = ((written - have + i) % WINDOW).toInt()
                re[startPad + i] = ring[src] * window[startPad + i]
            }
            fft.transform(re, im)
            // Hann coherent gain 0.5: a full-scale sine peaks at N/4.
            val norm = WINDOW / 4.0
            for (b in 0 until BANDS) {
                val lo = bandEdges[b]
                val hi = bandEdges[b + 1].coerceAtLeast(lo + 1)
                var sum = 0.0
                for (bin in lo until hi) {
                    sum += sqrt(re[bin] * re[bin] + im[bin] * im[bin])
                }
                val v = (sum / (hi - lo)) / norm
                pending.add(v)
                cache.writeFloat(v.toFloat())
            }
            val rmsL = if (hopSamples > 0) sqrt(sumL2 / hopSamples) else 0.0
            val rmsR = if (hopSamples > 0) sqrt(sumR2 / hopSamples) else 0.0
            sumL2 = 0.0
            sumR2 = 0.0
            hopSamples = 0
            pending.add(rmsL)
            pending.add(rmsR)
            cache.writeFloat(rmsL.toFloat())
            cache.writeFloat(rmsR.toFloat())
            frameCount++
            if (pending.size >= CHUNK_FRAMES * FRAME_FLOATS) flushPending(false)
        }

        fun pushSample(mix: Float, l: Float, r: Float) {
            sumL2 += l.toDouble() * l
            sumR2 += r.toDouble() * r
            hopSamples++
            ring[(written % WINDOW).toInt()] = mix
            written++
            if (written >= nextFrameAt) {
                analyzeFrame()
                nextFrameAt += hop
            }
        }

        val bufferInfo = MediaCodec.BufferInfo()
        var inputDone = false
        var outputDone = false
        try {
            while (!outputDone && alive(job)) {
                if (!inputDone) {
                    val inIndex = codec.dequeueInputBuffer(10_000)
                    if (inIndex >= 0) {
                        val buf = codec.getInputBuffer(inIndex)!!
                        val size = extractor.readSampleData(buf, 0)
                        if (size < 0) {
                            codec.queueInputBuffer(
                                inIndex, 0, 0, 0, MediaCodec.BUFFER_FLAG_END_OF_STREAM
                            )
                            inputDone = true
                        } else {
                            codec.queueInputBuffer(inIndex, 0, size, extractor.sampleTime, 0)
                            extractor.advance()
                        }
                    }
                }

                val outIndex = codec.dequeueOutputBuffer(bufferInfo, 10_000)
                when {
                    outIndex == MediaCodec.INFO_OUTPUT_FORMAT_CHANGED -> {
                        val f = codec.outputFormat
                        sampleRate = f.getIntOrDefault(MediaFormat.KEY_SAMPLE_RATE, sampleRate)
                        channels = f.getIntOrDefault(MediaFormat.KEY_CHANNEL_COUNT, channels)
                        pcmFloat = f.getIntOrDefault(MediaFormat.KEY_PCM_ENCODING,
                            AudioFormat.ENCODING_PCM_16BIT) == AudioFormat.ENCODING_PCM_FLOAT
                        hop = sampleRate.toDouble() / FRAME_RATE
                        bandEdges = bandEdgeBins(sampleRate)
                    }
                    outIndex >= 0 -> {
                        val buf = codec.getOutputBuffer(outIndex)!!
                        buf.position(bufferInfo.offset)
                        buf.limit(bufferInfo.offset + bufferInfo.size)
                        // Channel 0 = left, channel 1 = right (mono:
                        // both needles read the same); extra surround
                        // channels only join the FFT mix.
                        if (pcmFloat) {
                            val floats = buf.order(ByteOrder.nativeOrder()).asFloatBuffer()
                            val frame = FloatArray(channels)
                            while (floats.remaining() >= channels) {
                                floats.get(frame)
                                var mix = 0f
                                for (c in frame) mix += c
                                val l = frame[0]
                                val r = if (channels > 1) frame[1] else l
                                pushSample(mix / channels, l, r)
                            }
                        } else {
                            val shorts = buf.order(ByteOrder.nativeOrder()).asShortBuffer()
                            val frame = ShortArray(channels)
                            while (shorts.remaining() >= channels) {
                                shorts.get(frame)
                                var mix = 0f
                                for (c in frame) mix += c / 32768f
                                val l = frame[0] / 32768f
                                val r = if (channels > 1) frame[1] / 32768f else l
                                pushSample(mix / channels, l, r)
                            }
                        }
                        codec.releaseOutputBuffer(outIndex, false)
                        if (bufferInfo.flags and MediaCodec.BUFFER_FLAG_END_OF_STREAM != 0) {
                            outputDone = true
                        }
                    }
                }
            }
        } finally {
            try { codec.stop() } catch (_: Exception) {}
            try { codec.release() } catch (_: Exception) {}
            try { extractor.release() } catch (_: Exception) {}
            try { cache.close() } catch (_: Exception) {}
        }

        if (alive(job) && outputDone) {
            // Patch the frame count into the header, promote the file.
            java.io.RandomAccessFile(tmpFile, "rw").use {
                it.seek(0)
                it.writeInt(frameCount)
            }
            tmpFile.renameTo(cacheOut)
            trimCache()
            flushPending(true)
        } else {
            tmpFile.delete()
        }
    }

    /** 13 bin edges, log-spaced ~40 Hz → 14 kHz (capped below Nyquist). */
    private fun bandEdgeBins(sampleRate: Int): IntArray {
        val binHz = sampleRate.toDouble() / WINDOW
        val lo = 40.0
        val hi = min(14000.0, sampleRate / 2 * 0.9)
        return IntArray(BANDS + 1) { i ->
            val f = lo * Math.pow(hi / lo, i.toDouble() / BANDS)
            (f / binHz).toInt().coerceIn(1, WINDOW / 2 - 1)
        }
    }

    private fun MediaFormat.getIntOrDefault(name: String, fallback: Int): Int =
        if (containsKey(name)) getInteger(name) else fallback
}

/** Iterative radix-2 complex FFT with precomputed twiddles. */
private class Fft(private val n: Int) {
    private val cosTable = DoubleArray(n / 2) { cos(2 * PI * it / n) }
    private val sinTable = DoubleArray(n / 2) { sin(2 * PI * it / n) }
    private val reversed = IntArray(n).also { table ->
        var bits = 0
        while ((1 shl bits) < n) bits++
        for (i in 0 until n) {
            table[i] = Integer.reverse(i) ushr (32 - bits)
        }
    }

    fun transform(re: DoubleArray, im: DoubleArray) {
        for (i in 0 until n) {
            val j = reversed[i]
            if (j > i) {
                var t = re[i]; re[i] = re[j]; re[j] = t
                t = im[i]; im[i] = im[j]; im[j] = t
            }
        }
        var size = 2
        while (size <= n) {
            val half = size / 2
            val step = n / size
            var i = 0
            while (i < n) {
                var k = 0
                for (j in i until i + half) {
                    val l = j + half
                    val tre = re[l] * cosTable[k] + im[l] * sinTable[k]
                    val tim = -re[l] * sinTable[k] + im[l] * cosTable[k]
                    re[l] = re[j] - tre
                    im[l] = im[j] - tim
                    re[j] += tre
                    im[j] += tim
                    k += step
                }
                i += size
            }
            size = size shl 1
        }
    }
}
