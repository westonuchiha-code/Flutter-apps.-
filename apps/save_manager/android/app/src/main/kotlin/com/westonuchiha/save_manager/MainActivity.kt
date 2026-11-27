package com.westonuchiha.save_manager

import android.Manifest
import android.content.ActivityNotFoundException
import android.content.ComponentName
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.os.Environment
import android.provider.Settings
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

/** Storage access (the saves live in the emulators' own folders), and
 *  Start game handed to the XMB Frontend ("startInXmb"). */
class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "save_manager/android")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "hasAllFiles" -> result.success(hasAllFiles())
                    "requestAllFiles" -> {
                        requestAllFiles()
                        result.success(null)
                    }
                    "storageRoot" -> result.success(Environment.getExternalStorageDirectory().path)
                    "startInXmb" -> {
                        @Suppress("UNCHECKED_CAST")
                        val extras = call.argument<Map<String, String>>("extras") ?: emptyMap()
                        result.success(
                            startInXmb(
                                call.argument<String>("package") ?: "",
                                call.argument<String>("activity") ?: "",
                                extras
                            )
                        )
                    }
                    else -> result.notImplemented()
                }
            }
    }

    /// Opens the XMB Frontend with the save's game in the extras: "ok",
    /// "missing" (not installed), or what went wrong.
    private fun startInXmb(pkg: String, activity: String, extras: Map<String, String>): String {
        try {
            packageManager.getPackageInfo(pkg, 0)
        } catch (e: PackageManager.NameNotFoundException) {
            return "missing"
        }
        val intent = Intent(Intent.ACTION_MAIN).apply {
            component = ComponentName(pkg, activity)
            for ((k, v) in extras) putExtra(k, v)
            // A running XMB comes to the front and hears it (onNewIntent).
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP)
        }
        return try {
            startActivity(intent)
            "ok"
        } catch (e: ActivityNotFoundException) {
            "missing"
        } catch (e: SecurityException) {
            "Android refused: ${e.message}"
        }
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
