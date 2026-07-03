package com.hanamimi.app

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        val mediaStore = MediaStoreChannel(applicationContext)
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "hanamimi/mediastore",
        ).setMethodCallHandler { call, result -> mediaStore.handle(call, result) }
    }
}
