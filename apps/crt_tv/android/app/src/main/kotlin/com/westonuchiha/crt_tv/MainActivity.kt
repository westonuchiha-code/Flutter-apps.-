package com.westonuchiha.crt_tv

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

/// The TV's Android side (MethodChannel "crt_tv/android"): "All files"
/// access, which the video player needs to open videos anywhere by their
/// path, and the storage roots (internal storage, SD cards).
class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "crt_tv/android")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "hasAllFiles" -> result.success(hasAllFiles())
                    "requestAllFiles" -> {
                        requestAllFiles()
                        result.success(null)
                    }
                    "storageRoots" -> result.success(storageRoots())
                    else -> result.notImplemented()
                }
            }
    }

    private fun hasAllFiles(): Boolean =
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            Environment.isExternalStorageManager()
        } else {
            checkSelfPermission(Manifest.permission.READ_EXTERNAL_STORAGE) ==
                PackageManager.PERMISSION_GRANTED &&
                checkSelfPermission(Manifest.permission.WRITE_EXTERNAL_STORAGE) ==
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

    /// Internal storage and SD cards: the part of each app-files folder
    /// before "/Android/".
    private fun storageRoots(): List<String> {
        val out = mutableListOf<String>()
        for (dir in getExternalFilesDirs(null)) {
            val path = dir?.absolutePath ?: continue
            val i = path.indexOf("/Android/")
            out.add(if (i > 0) path.substring(0, i) else path)
        }
        if (out.isEmpty()) out.add(Environment.getExternalStorageDirectory().absolutePath)
        return out.distinct()
    }
}
