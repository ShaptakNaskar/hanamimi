package com.hanamimi.app

import android.media.audiofx.Visualizer
import android.os.Handler
import android.os.Looper
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel

/**
 * Attaches android.media.audiofx.Visualizer to the playback session and
 * streams raw FFT byte arrays to Dart at ~30 Hz.
 *
 * Method channel "hanamimi/visualizer": attach(sessionId) / detach.
 * Event channel  "hanamimi/visualizer/fft": FFT ByteArray stream.
 */
class VisualizerChannel : EventChannel.StreamHandler {
    private var visualizer: Visualizer? = null
    private var events: EventChannel.EventSink? = null
    private var attachedSessionId: Int? = null
    private val mainHandler = Handler(Looper.getMainLooper())

    fun handle(call: io.flutter.plugin.common.MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "attach" -> {
                val sessionId = call.argument<Number>("sessionId")!!.toInt()
                result.success(attach(sessionId))
            }
            "detach" -> {
                detach()
                result.success(null)
            }
            else -> result.notImplemented()
        }
    }

    private fun attach(sessionId: Int): Boolean {
        if (attachedSessionId == sessionId && visualizer != null) return true
        detach()
        return try {
            val v = Visualizer(sessionId)
            v.captureSize = Visualizer.getCaptureSizeRange()[1]
            val rate = minOf(Visualizer.getMaxCaptureRate(), 30_000)
            v.setDataCaptureListener(
                object : Visualizer.OnDataCaptureListener {
                    override fun onWaveFormDataCapture(
                        v: Visualizer?, waveform: ByteArray?, samplingRate: Int
                    ) {}

                    override fun onFftDataCapture(
                        v: Visualizer?, fft: ByteArray?, samplingRate: Int
                    ) {
                        if (fft != null) {
                            mainHandler.post { events?.success(fft) }
                        }
                    }
                },
                rate, false, true,
            )
            v.enabled = true
            visualizer = v
            attachedSessionId = sessionId
            true
        } catch (e: Exception) {
            // No RECORD_AUDIO permission or bad session — caller falls back.
            false
        }
    }

    private fun detach() {
        visualizer?.let {
            try {
                it.enabled = false
                it.release()
            } catch (_: Exception) {
            }
        }
        visualizer = null
        attachedSessionId = null
    }

    override fun onListen(arguments: Any?, sink: EventChannel.EventSink?) {
        events = sink
    }

    override fun onCancel(arguments: Any?) {
        events = null
    }
}
