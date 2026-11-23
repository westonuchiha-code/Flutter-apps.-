package com.westonuchiha.audio_kit

import android.Manifest
import android.content.pm.PackageManager
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.embedding.engine.plugins.activity.ActivityAware
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.PluginRegistry

/** Asks Android for microphone access. */
class AudioKitPlugin :
    FlutterPlugin,
    ActivityAware,
    MethodChannel.MethodCallHandler,
    PluginRegistry.RequestPermissionsResultListener {

    private lateinit var channel: MethodChannel
    private var binding: ActivityPluginBinding? = null
    private var pending: MethodChannel.Result? = null

    override fun onAttachedToEngine(b: FlutterPlugin.FlutterPluginBinding) {
        channel = MethodChannel(b.binaryMessenger, "audio_kit")
        channel.setMethodCallHandler(this)
    }

    override fun onDetachedFromEngine(b: FlutterPlugin.FlutterPluginBinding) {
        channel.setMethodCallHandler(null)
    }

    override fun onAttachedToActivity(b: ActivityPluginBinding) {
        binding = b
        b.addRequestPermissionsResultListener(this)
    }

    override fun onDetachedFromActivityForConfigChanges() = onDetachedFromActivity()

    override fun onReattachedToActivityForConfigChanges(b: ActivityPluginBinding) =
        onAttachedToActivity(b)

    override fun onDetachedFromActivity() {
        binding?.removeRequestPermissionsResultListener(this)
        binding = null
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        if (call.method != "requestMic") return result.notImplemented()
        val activity = binding?.activity ?: return result.success(false)
        if (activity.checkSelfPermission(Manifest.permission.RECORD_AUDIO) ==
            PackageManager.PERMISSION_GRANTED
        ) {
            return result.success(true)
        }
        if (pending != null) return result.success(false)
        pending = result
        activity.requestPermissions(arrayOf(Manifest.permission.RECORD_AUDIO), REQUEST)
    }

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray,
    ): Boolean {
        if (requestCode != REQUEST) return false
        val result = pending ?: return true
        pending = null
        result.success(
            grantResults.isNotEmpty() && grantResults[0] == PackageManager.PERMISSION_GRANTED,
        )
        return true
    }

    companion object {
        private const val REQUEST = 0x6d69
    }
}
