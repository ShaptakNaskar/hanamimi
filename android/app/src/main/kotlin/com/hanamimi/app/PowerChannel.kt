package com.hanamimi.app

import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.PowerManager
import android.provider.Settings
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

/**
 * Battery-optimization exemption. Aggressive OEM battery management kills
 * the audio-service process in the background, which pauses playback the
 * user never paused. Exempting the app from Doze/App-Standby keeps the
 * foreground playback service alive.
 */
class PowerChannel(private val context: Context) {
    fun handle(call: MethodCall, result: MethodChannel.Result) {
        val pm = context.getSystemService(Context.POWER_SERVICE) as PowerManager
        when (call.method) {
            "isIgnoringBatteryOptimizations" ->
                result.success(pm.isIgnoringBatteryOptimizations(context.packageName))

            // The direct allow/deny dialog (ACTION_REQUEST_…). Fine for a
            // sideloaded build; a Play-Store build should switch to
            // ACTION_IGNORE_BATTERY_OPTIMIZATION_SETTINGS (the list) to
            // satisfy policy.
            "requestIgnoreBatteryOptimizations" -> {
                try {
                    val intent = Intent(
                        Settings.ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS,
                        Uri.parse("package:${context.packageName}"),
                    ).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                    context.startActivity(intent)
                    result.success(true)
                } catch (e: Exception) {
                    // Fall back to the app's battery settings page.
                    try {
                        context.startActivity(
                            Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS)
                                .setData(Uri.parse("package:${context.packageName}"))
                                .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK),
                        )
                        result.success(true)
                    } catch (e2: Exception) {
                        result.success(false)
                    }
                }
            }

            else -> result.notImplemented()
        }
    }
}
