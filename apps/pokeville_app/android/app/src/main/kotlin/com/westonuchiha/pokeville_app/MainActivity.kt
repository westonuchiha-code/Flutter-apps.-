package com.westonuchiha.pokeville_app

import android.Manifest
import android.content.ActivityNotFoundException
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.os.Environment
import android.provider.Settings
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

/** Storage access: the saves live in the emulators' own folders. */
class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "pokeville/android")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "hasAllFiles" -> result.success(hasAllFiles())
                    "requestAllFiles" -> {
                        requestAllFiles()
                        result.success(null)
                    }
                    "storageRoot" -> result.success(Environment.getExternalStorageDirectory().path)
                    "deviceModel" -> result.success("${Build.MANUFACTURER} ${Build.MODEL}")
                    "sharedToken" -> result.success(sharedToken())
                    "openUrl" -> {
                        val urls = call.argument<List<String>>("urls") ?: emptyList()
                        result.success(openUrl(urls))
                    }
                    else -> result.notImplemented()
                }
            }
    }

    /// The XMB Frontend's Cross-Save sign-in (its TokenProvider; only apps
    /// signed with the same key may read it). "" when the XMB isn't
    /// installed, isn't signed in, or won't answer.
    private fun sharedToken(): String = try {
        contentResolver.query(
            Uri.parse("content://com.westonuchiha.xmb_frontend.crosssave/token"),
            null, null, null, null
        )?.use { c -> if (c.moveToFirst()) c.getString(0) ?: "" else "" } ?: ""
    } catch (e: SecurityException) {
        ""
    } catch (e: IllegalArgumentException) {
        ""
    }

    /// Opens the first of [urls] something can show; false when none.
    private fun openUrl(urls: List<String>): Boolean {
        for (u in urls) {
            try {
                startActivity(Intent(Intent.ACTION_VIEW, Uri.parse(u)).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
                return true
            } catch (e: ActivityNotFoundException) {
            } catch (e: SecurityException) {
            }
        }
        return false
    }

    private fun hasAllFiles(): Boolean =
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            Environment.isExternalStorageManager()
        } else {
            checkSelfPermission(Manifest.permission.READ_EXTERNAL_STORAGE) ==
                PackageManager.PERMISSION_GRANTED
        }

    private fun requestAllFiles() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            try {
                startActivity(
                    Intent(
                        Settings.ACTION_MANAGE_APP_ALL_FILES_ACCESS_PERMISSION,
                        Uri.parse("package:$packageName")
                    )
                )
            } catch (e: ActivityNotFoundException) {
                startActivity(Intent(Settings.ACTION_MANAGE_ALL_FILES_ACCESS_PERMISSION))
            }
        } else {
            requestPermissions(
                arrayOf(
                    Manifest.permission.READ_EXTERNAL_STORAGE,
                    Manifest.permission.WRITE_EXTERNAL_STORAGE
                ),
                1
            )
        }
    }
}
