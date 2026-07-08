package com.hanamimi.app

import android.content.Context
import android.content.Intent
import android.hardware.input.InputManager
import android.net.Uri
import android.os.Bundle
import android.os.Handler
import android.provider.MediaStore
import android.view.KeyEvent
import android.view.MotionEvent
import com.ryanheise.audioservice.AudioServiceActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel
import org.flame_engine.gamepads_android.GamepadsCompatibleActivity

// AudioServiceActivity is our base (audio_service needs it); we also
// implement GamepadsCompatibleActivity so the `gamepads` plugin can
// receive controller input — without it the plugin ClassCasts the
// activity and crashes on launch. The handlers are forwarded from the
// standard dispatch overrides below.
class MainActivity : AudioServiceActivity(), GamepadsCompatibleActivity {
    private var openWith: MethodChannel? = null
    private var pendingMedia: Map<String, String?>? = null

    private var gamepadKeyHandler: ((KeyEvent) -> Boolean)? = null
    private var gamepadMotionHandler: ((MotionEvent) -> Boolean)? = null

    override fun registerInputDeviceListener(
        listener: InputManager.InputDeviceListener,
        handler: Handler?,
    ) {
        (getSystemService(Context.INPUT_SERVICE) as InputManager)
            .registerInputDeviceListener(listener, handler)
    }

    override fun registerKeyEventHandler(handler: (KeyEvent) -> Boolean) {
        gamepadKeyHandler = handler
    }

    override fun registerMotionEventHandler(handler: (MotionEvent) -> Boolean) {
        gamepadMotionHandler = handler
    }

    override fun dispatchKeyEvent(event: KeyEvent): Boolean {
        if (gamepadKeyHandler?.invoke(event) == true) return true
        return super.dispatchKeyEvent(event)
    }

    override fun dispatchGenericMotionEvent(event: MotionEvent): Boolean {
        if (gamepadMotionHandler?.invoke(event) == true) return true
        return super.dispatchGenericMotionEvent(event)
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        val mediaStore = MediaStoreChannel(applicationContext)
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "hanamimi/mediastore",
        ).setMethodCallHandler { call, result -> mediaStore.handle(call, result) }

        val fft = FftExtractorChannel(applicationContext)
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "hanamimi/fft",
        ).setMethodCallHandler { call, result -> fft.handle(call, result) }
        EventChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "hanamimi/fft/frames",
        ).setStreamHandler(fft)

        // Live audio-output info for Nerd mode (output route, codecs).
        val audioInfo = AudioInfoChannel(applicationContext)
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "hanamimi/audio_info",
        ).setMethodCallHandler { call, result -> audioInfo.handle(call, result) }

        // In-app updater: checks main-v releases, installs the matching ABI.
        val updater = UpdaterChannel(applicationContext)
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "hanamimi/updater",
        ).setMethodCallHandler { call, result -> updater.handle(call, result) }

        // Battery-optimization exemption (keeps background playback alive)
        // + keep-screen-on, which needs the activity window — hence `this`.
        val power = PowerChannel(this)
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "hanamimi/power",
        ).setMethodCallHandler { call, result -> power.handle(call, result) }

        openWith = MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "hanamimi/open_with",
        ).apply {
            setMethodCallHandler { call, result ->
                when (call.method) {
                    "getPendingMedia" -> {
                        result.success(pendingMedia)
                        pendingMedia = null
                    }
                    else -> result.notImplemented()
                }
            }
        }
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        intent?.let { captureViewIntent(it) }
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        captureViewIntent(intent)
    }

    /**
     * "Open with Hanamimi" from file managers etc. On a cold start the
     * Dart handler isn't attached yet, so the payload also parks in
     * [pendingMedia] for the getPendingMedia poll; the live invoke
     * clears it on success so it can't replay on a later launch.
     */
    private fun captureViewIntent(intent: Intent) {
        if (intent.action != Intent.ACTION_VIEW) return
        val uri = intent.data ?: return
        val payload = describeMedia(uri)
        pendingMedia = payload
        openWith?.invokeMethod("openMedia", payload, object : MethodChannel.Result {
            override fun success(result: Any?) {
                if (pendingMedia === payload) pendingMedia = null
            }

            override fun error(code: String, message: String?, details: Any?) {}
            override fun notImplemented() {}
        })
    }

    /** Resolves a real file path + display name where the provider allows it. */
    private fun describeMedia(uri: Uri): Map<String, String?> {
        var path: String? = null
        var title: String? = null
        if (uri.scheme == "file") {
            path = uri.path
            title = uri.lastPathSegment
        } else {
            try {
                contentResolver.query(
                    uri,
                    arrayOf(MediaStore.MediaColumns.DATA, MediaStore.MediaColumns.DISPLAY_NAME),
                    null, null, null,
                )?.use { c ->
                    if (c.moveToFirst()) {
                        val dataCol = c.getColumnIndex(MediaStore.MediaColumns.DATA)
                        val nameCol = c.getColumnIndex(MediaStore.MediaColumns.DISPLAY_NAME)
                        if (dataCol >= 0) path = c.getString(dataCol)
                        if (nameCol >= 0) title = c.getString(nameCol)
                    }
                }
            } catch (_: Exception) {
                // Provider without those columns — play via the uri.
            }
        }
        return mapOf("uri" to uri.toString(), "path" to path, "title" to title)
    }
}
