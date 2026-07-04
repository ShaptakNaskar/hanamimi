package com.hanamimi.app

import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.provider.Settings
import androidx.core.content.FileProvider
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.File

/**
 * In-app update installer (channel "hanamimi/updater").
 *
 *   canInstall()      -> Bool   (REQUEST_INSTALL_PACKAGES granted?)
 *   openInstallPerm() -> null   (jump to the unknown-sources setting)
 *   install(path)     -> Bool   (hand the downloaded APK to the
 *                                package installer via FileProvider)
 *
 * The app downloads the release APK itself (with progress in Flutter),
 * then this launches the system installer sheet — the closest Android
 * lets a sideloaded app get to "self update".
 */
class UpdaterChannel(private val context: Context) {
    fun handle(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "canInstall" -> result.success(
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O)
                    context.packageManager.canRequestPackageInstalls()
                else true
            )
            "openInstallPerm" -> {
                val intent = Intent(
                    Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES,
                    Uri.parse("package:${context.packageName}"),
                ).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                context.startActivity(intent)
                result.success(null)
            }
            "install" -> {
                val path = call.argument<String>("path")
                if (path == null) {
                    result.success(false)
                    return
                }
                result.success(install(File(path)))
            }
            else -> result.notImplemented()
        }
    }

    private fun install(apk: File): Boolean {
        if (!apk.exists()) return false
        return try {
            val uri = FileProvider.getUriForFile(
                context, "${context.packageName}.fileprovider", apk)
            val intent = Intent(Intent.ACTION_VIEW).apply {
                setDataAndType(uri, "application/vnd.android.package-archive")
                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
            }
            context.startActivity(intent)
            true
        } catch (_: Exception) {
            false
        }
    }
}
