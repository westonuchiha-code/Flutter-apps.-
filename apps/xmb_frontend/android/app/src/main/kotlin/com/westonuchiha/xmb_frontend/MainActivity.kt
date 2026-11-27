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
    private var channel: MethodChannel? = null

    /// Start game from the Save Manager app, waiting for the menu to ask
    /// ("takeStartRequest"): extras start_game_system / _title / _serial /
    /// _file. Only a library game the menu matches can start this way.
    private var startRequest: Map<String, String>? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        // Emulators take games as file paths (file:// data), which Android
        // otherwise refuses to hand to another app.
        StrictMode.setVmPolicy(StrictMode.VmPolicy.Builder().build())
        // Cold start: the request came with the launching intent (not again
        // when Android recreates the activity from its history).
        if (savedInstanceState == null) keepStartRequest(intent)
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        // Warm: the menu is running; tell it to ask.
        if (keepStartRequest(intent)) channel?.invokeMethod("startRequest", null)
    }

    private fun keepStartRequest(intent: Intent?): Boolean {
        val system = intent?.getStringExtra("start_game_system") ?: return false
        if (system.isBlank()) return false
        startRequest = mapOf(
            "start_game_system" to system,
            "start_game_title" to (intent.getStringExtra("start_game_title") ?: ""),
            "start_game_serial" to (intent.getStringExtra("start_game_serial") ?: ""),
            "start_game_file" to (intent.getStringExtra("start_game_file") ?: ""),
        )
        // Taken once: a later recreate doesn't start it again.
        intent.removeExtra("start_game_system")
        return true
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        val ch = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "xmb/android")
        channel = ch
        ch.setMethodCallHandler { call, result ->
                when (call.method) {
                    "takeStartRequest" -> {
                        result.success(startRequest)
                        startRequest = null
                    }
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
                    "openUrl" -> {
                        val urls = call.argument<List<String>>("urls") ?: emptyList()
                        result.success(openUrl(urls))
                    }
                    // Cross-Save's token, for the Pokéville app (TokenProvider).
                    "setSharedToken" -> {
                        TokenProvider.write(this, call.argument<String>("token") ?: "")
                        result.success(null)
                    }
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

    /// Opens the first of [urls] something can show (Google Play's app,
    /// else the browser); false when none could be opened.
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
