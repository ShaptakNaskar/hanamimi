package com.hanamimi.app

import android.content.Context
import android.media.AudioDeviceInfo
import android.media.AudioManager
import android.media.MediaExtractor
import android.media.MediaFormat
import android.net.Uri
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

/**
 * Live audio facts for Nerd mode (M28+):
 *
 *   output()      -> { route, name, sampleRate }
 *   probe(path)   -> { codec, sampleRate, channels, bitrate }  (local files)
 *
 * On "route": we report where the mix is going (Bluetooth / Wired /
 * USB / Speaker) plus the device's own name and the system output
 * sample rate. The *negotiated* Bluetooth codec (LDAC / aptX / AAC /
 * SBC) is deliberately NOT reported: BluetoothA2dp.getCodecStatus is
 * @SystemApi guarded by BLUETOOTH_PRIVILEGED, a signature-level
 * permission a sideloaded app cannot hold, so any value would be a
 * guess. The source stream's codec + bitrate (from the resolver) is the
 * honest quality signal and is shown alongside this.
 */
class AudioInfoChannel(private val context: Context) {
    private val audio = context.getSystemService(Context.AUDIO_SERVICE) as AudioManager

    fun handle(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "output" -> result.success(outputInfo())
            "probe" -> {
                val path = call.argument<String>("path")
                result.success(if (path == null) null else probe(path))
            }
            else -> result.notImplemented()
        }
    }

    private fun outputInfo(): Map<String, Any?> {
        val devices = audio.getDevices(AudioManager.GET_DEVICES_OUTPUTS)

        // Pick the device the media mix is most likely routed to. There's
        // no public "current output" API for media before API 31, so
        // infer from what's connected + the legacy routing flags.
        @Suppress("DEPRECATION")
        val active: AudioDeviceInfo? = when {
            audio.isBluetoothA2dpOn ->
                devices.firstOrNull {
                    it.type == AudioDeviceInfo.TYPE_BLUETOOTH_A2DP ||
                        it.type == AudioDeviceInfo.TYPE_BLE_HEADSET
                }
            else -> devices.firstOrNull {
                it.type == AudioDeviceInfo.TYPE_WIRED_HEADPHONES ||
                    it.type == AudioDeviceInfo.TYPE_WIRED_HEADSET ||
                    it.type == AudioDeviceInfo.TYPE_USB_HEADSET ||
                    it.type == AudioDeviceInfo.TYPE_USB_DEVICE
            }
        }

        val route = when (active?.type) {
            AudioDeviceInfo.TYPE_BLUETOOTH_A2DP,
            AudioDeviceInfo.TYPE_BLE_HEADSET -> "Bluetooth"
            AudioDeviceInfo.TYPE_WIRED_HEADPHONES,
            AudioDeviceInfo.TYPE_WIRED_HEADSET -> "Wired"
            AudioDeviceInfo.TYPE_USB_HEADSET,
            AudioDeviceInfo.TYPE_USB_DEVICE -> "USB"
            else -> "Speaker"
        }

        val name = active?.productName?.toString()?.takeIf { it.isNotBlank() }
        val sampleRate =
            audio.getProperty(AudioManager.PROPERTY_OUTPUT_SAMPLE_RATE)?.toIntOrNull()

        return mapOf(
            "route" to route,
            "name" to name,
            "sampleRate" to sampleRate,
        )
    }

    private fun probe(path: String): Map<String, Any?>? {
        val extractor = MediaExtractor()
        return try {
            if (path.startsWith("content://")) {
                extractor.setDataSource(context, Uri.parse(path), null)
            } else {
                extractor.setDataSource(path)
            }
            var format: MediaFormat? = null
            for (i in 0 until extractor.trackCount) {
                val f = extractor.getTrackFormat(i)
                if ((f.getString(MediaFormat.KEY_MIME) ?: "").startsWith("audio/")) {
                    format = f
                    break
                }
            }
            val f = format ?: return null
            val mime = f.getString(MediaFormat.KEY_MIME)
            mapOf(
                "codec" to codecLabel(mime),
                "sampleRate" to f.optInt(MediaFormat.KEY_SAMPLE_RATE),
                "channels" to f.optInt(MediaFormat.KEY_CHANNEL_COUNT),
                "bitrate" to f.optInt(MediaFormat.KEY_BIT_RATE),
            )
        } catch (_: Exception) {
            null
        } finally {
            try { extractor.release() } catch (_: Exception) {}
        }
    }

    private fun codecLabel(mime: String?): String? = when (mime) {
        null -> null
        "audio/mpeg" -> "MP3"
        "audio/mp4a-latm" -> "AAC"
        "audio/opus" -> "Opus"
        "audio/vorbis" -> "Vorbis"
        "audio/flac" -> "FLAC"
        "audio/raw" -> "PCM"
        "audio/ac3" -> "AC-3"
        "audio/eac3" -> "E-AC-3"
        "audio/amr-wb" -> "AMR-WB"
        "audio/amr" -> "AMR"
        else -> mime.removePrefix("audio/").uppercase()
    }

    private fun MediaFormat.optInt(key: String): Int? =
        if (containsKey(key)) getInteger(key) else null
}
