package com.westonuchiha.ambience_machine

import android.Manifest
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private var channel: MethodChannel? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        val ch = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "ambience/service")
        channel = ch
        PlaybackService.onStopRequested = {
            runOnUiThread { ch.invokeMethod("stopRequested", null) }
        }
        ch.setMethodCallHandler { call, result ->
            when (call.method) {
                "start" -> {
                    askForNotifications()
                    val intent = Intent(this, PlaybackService::class.java)
                        .putExtra(PlaybackService.EXTRA_TITLE, call.argument<String>("title"))
                        .putExtra(PlaybackService.EXTRA_TEXT, call.argument<String>("text"))
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                        startForegroundService(intent)
                    } else {
                        startService(intent)
                    }
                    result.success(true)
                }
                "stop" -> {
                    stopService(Intent(this, PlaybackService::class.java))
                    result.success(true)
                }
                else -> result.notImplemented()
            }
        }
    }

    /** Android 13+: the playback notification needs permission to show. */
    private fun askForNotifications() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU &&
            checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) != PackageManager.PERMISSION_GRANTED
        ) {
            requestPermissions(arrayOf(Manifest.permission.POST_NOTIFICATIONS), 7)
        }
    }

    override fun onDestroy() {
        PlaybackService.onStopRequested = null
        stopService(Intent(this, PlaybackService::class.java))
        super.onDestroy()
    }
}
