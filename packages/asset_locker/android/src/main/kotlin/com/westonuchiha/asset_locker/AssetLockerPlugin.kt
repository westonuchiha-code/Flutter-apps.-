package com.westonuchiha.asset_locker

import android.app.Activity
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.provider.DocumentsContract
import androidx.documentfile.provider.DocumentFile
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.embedding.engine.plugins.activity.ActivityAware
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.PluginRegistry
import java.util.concurrent.Executors

/**
 * Shared-folder access through Android's Storage Access Framework.
 * Paths are relative to the picked folder, separated by '/'.
 */
class AssetLockerPlugin :
    FlutterPlugin,
    ActivityAware,
    MethodChannel.MethodCallHandler,
    PluginRegistry.ActivityResultListener {

    private lateinit var channel: MethodChannel
    private lateinit var context: Context
    private var binding: ActivityPluginBinding? = null
    private var pending: MethodChannel.Result? = null
    private val io = Executors.newSingleThreadExecutor()
    private val main = Handler(Looper.getMainLooper())

    override fun onAttachedToEngine(b: FlutterPlugin.FlutterPluginBinding) {
        context = b.applicationContext
        channel = MethodChannel(b.binaryMessenger, "asset_locker")
        channel.setMethodCallHandler(this)
    }

    override fun onDetachedFromEngine(b: FlutterPlugin.FlutterPluginBinding) {
        channel.setMethodCallHandler(null)
    }

    override fun onAttachedToActivity(b: ActivityPluginBinding) {
        binding = b
        b.addActivityResultListener(this)
    }

    override fun onDetachedFromActivityForConfigChanges() = onDetachedFromActivity()

    override fun onReattachedToActivityForConfigChanges(b: ActivityPluginBinding) =
        onAttachedToActivity(b)

    override fun onDetachedFromActivity() {
        binding?.removeActivityResultListener(this)
        binding = null
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "pickFolder" -> pickFolder(call.argument<String>("initial"), result)
            "hasAccess" -> result.success(hasAccess(call.argument<String>("uri")!!))
            else -> background(result) { run(call) }
        }
    }

    private fun run(call: MethodCall): Any? {
        val tree = Uri.parse(call.argument<String>("uri")!!)
        val path = call.argument<String>("path") ?: ""
        return when (call.method) {
            "list" -> {
                val dir = find(tree, path) ?: return emptyList<Any>()
                dir.listFiles().map {
                    mapOf(
                        "name" to (it.name ?: ""),
                        "isDir" to it.isDirectory,
                        "size" to it.length(),
                        "modified" to it.lastModified(),
                    )
                }
            }
            "read" -> {
                val file = find(tree, path) ?: return null
                if (!file.isFile) return null
                context.contentResolver.openInputStream(file.uri)?.use { it.readBytes() }
            }
            "write" -> {
                val bytes = call.argument<ByteArray>("bytes")!!
                val file = createFile(tree, path)
                    ?: throw IllegalStateException("Could not create $path")
                context.contentResolver.openOutputStream(file.uri, "wt")!!.use {
                    it.write(bytes)
                }
                true
            }
            "delete" -> find(tree, path)?.delete() ?: false
            else -> throw NotImplementedError(call.method)
        }
    }

    private fun segments(path: String) = path.split('/').filter { it.isNotEmpty() }

    private fun root(tree: Uri) =
        DocumentFile.fromTreeUri(context, tree)
            ?: throw IllegalStateException("Folder is not available")

    private fun find(tree: Uri, path: String): DocumentFile? {
        var doc: DocumentFile = root(tree)
        for (name in segments(path)) {
            doc = doc.findFile(name) ?: return null
        }
        return doc
    }

    private fun createFile(tree: Uri, path: String): DocumentFile? {
        val parts = segments(path)
        var dir = root(tree)
        for (name in parts.dropLast(1)) {
            val next = dir.findFile(name)
            dir = when {
                next == null -> dir.createDirectory(name) ?: return null
                next.isDirectory -> next
                else -> return null
            }
        }
        val name = parts.last()
        // octet-stream keeps the file name exactly as given (no extension added).
        return dir.findFile(name) ?: dir.createFile("application/octet-stream", name)
    }

    private fun hasAccess(uri: String): Boolean {
        val parsed = Uri.parse(uri)
        return context.contentResolver.persistedUriPermissions.any {
            it.uri == parsed && it.isReadPermission && it.isWritePermission
        }
    }

    private fun pickFolder(initial: String?, result: MethodChannel.Result) {
        val activity: Activity = binding?.activity
            ?: return result.error("no_activity", "No activity", null)
        if (pending != null) return result.error("busy", "Picker already open", null)
        val intent = Intent(Intent.ACTION_OPEN_DOCUMENT_TREE).apply {
            addFlags(
                Intent.FLAG_GRANT_READ_URI_PERMISSION or
                    Intent.FLAG_GRANT_WRITE_URI_PERMISSION or
                    Intent.FLAG_GRANT_PERSISTABLE_URI_PERMISSION,
            )
            if (initial != null && Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                putExtra(DocumentsContract.EXTRA_INITIAL_URI, Uri.parse(initial))
            }
        }
        pending = result
        activity.startActivityForResult(intent, REQUEST)
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?): Boolean {
        if (requestCode != REQUEST) return false
        val result = pending ?: return true
        pending = null
        val uri = data?.data
        if (resultCode != Activity.RESULT_OK || uri == null) {
            result.success(null)
            return true
        }
        context.contentResolver.takePersistableUriPermission(
            uri,
            Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_GRANT_WRITE_URI_PERMISSION,
        )
        result.success(uri.toString())
        return true
    }

    private fun background(result: MethodChannel.Result, work: () -> Any?) {
        io.execute {
            try {
                val value = work()
                main.post { result.success(value) }
            } catch (e: Exception) {
                main.post { result.error("io", e.message, null) }
            }
        }
    }

    companion object {
        private const val REQUEST = 0x4c6f
    }
}
