package com.hanamimi.app

import com.ryanheise.audioservice.AudioServiceActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : AudioServiceActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        val mediaStore = MediaStoreChannel(applicationContext)
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "hanamimi/mediastore",
        ).setMethodCallHandler { call, result -> mediaStore.handle(call, result) }
    }
}
