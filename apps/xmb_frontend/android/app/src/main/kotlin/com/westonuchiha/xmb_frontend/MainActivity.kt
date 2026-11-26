package com.westonuchiha.xmb_frontend

import android.Manifest
import android.content.ActivityNotFoundException
import android.content.ComponentName
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.os.Environment
import android.os.StrictMode
import android.provider.Settings
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File

/// The menu's Android side: which emulators are installed, storage access,
/// and starting games (MethodChannel "xmb/android").
class MainActivity : FlutterActivity() {
    private val io = java.util.concurrent.Executors.newSingleThreadExecutor()
    private val main = android.os.Handler(android.os.Looper.getMainLooper())
    private val comics by lazy { ComicArchives(cacheDir) }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        // Emulators take games as file paths (file:// data), which Android
        // otherwise refuses to hand to another app.
        StrictMode.setVmPolicy(StrictMode.VmPolicy.Builder().build())
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "xmb/android")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "installed" -> {
                        val pkgs = call.argument<List<String>>("packages") ?: emptyList()
                        result.success(pkgs.filter { isInstalled(it) })
                    }
                    "hasAllFiles" -> result.success(hasAllFiles())
                    "requestAllFiles" -> {
                        requestAllFiles()
                        result.success(null)
                    }
                    "storageRoots" -> result.success(storageRoots())
                    // the save manager's (packages/save_screens) storage root
                    "storageRoot" -> result.success(Environment.getExternalStorageDirectory().path)
                    "deviceModel" -> result.success("${Build.MANUFACTURER} ${Build.MODEL}")
                    "launch" -> {
                        @Suppress("UNCHECKED_CAST")
                        result.success(launch(call.arguments as Map<String, Any?>))
                    }
                    "comicList", "comicPage" -> {
                        val path = call.argument<String>("path") ?: ""
                        val name = call.argument<String>("name") ?: ""
                        val method = call.method
                        // Unpacking can take a moment: off the main thread.
                        io.execute {
                            try {
                                val v: Any = if (method == "comicList") comics.list(path)
                                    else comics.page(path, name)
                                main.post { result.success(v) }
                            } catch (e: Throwable) {
                                main.post { result.error("comic", e.message ?: e.toString(), null) }
                            }
                        }
                    }
                    else -> result.notImplemented()
                }
            }
    }

    private fun isInstalled(pkg: String): Boolean = try {
        packageManager.getPackageInfo(pkg, 0)
        true
    } catch (e: PackageManager.NameNotFoundException) {
        false
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

    /// Starts an app; returns an error message or null.
    private fun launch(spec: Map<String, Any?>): String? {
        val pkg = spec["package"] as? String ?: return "No app given."
        if (!isInstalled(pkg)) return "$pkg is not installed."
        val intent = Intent((spec["action"] as? String) ?: Intent.ACTION_MAIN)
        val activity = spec["activity"] as? String
        if (activity != null) {
            intent.component = ComponentName(pkg, activity)
        } else {
            intent.setPackage(pkg)
        }
        val data = spec["data"] as? String
        if (data != null) {
            intent.setDataAndType(Uri.fromFile(File(data)), (spec["type"] as? String) ?: "*/*")
            intent.addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
        }
        @Suppress("UNCHECKED_CAST")
        val extras = spec["extras"] as? Map<String, Any?> ?: emptyMap()
        for ((k, v) in extras) {
            when (v) {
                is String -> intent.putExtra(k, v)
                is List<*> -> intent.putExtra(k, v.map { it.toString() }.toTypedArray())
                is Boolean -> intent.putExtra(k, v)
                is Int -> intent.putExtra(k, v)
            }
        }
        intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        return try {
            startActivity(intent)
            null
        } catch (e: ActivityNotFoundException) {
            "Could not start it: ${e.message}"
        } catch (e: SecurityException) {
            "Android refused: ${e.message}"
        }
    }
}
