package com.westonuchiha.controller_lab

import android.content.Context
import android.hardware.input.InputManager
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.os.VibrationEffect
import android.view.InputDevice
import android.view.KeyEvent
import android.view.MotionEvent
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel

/// Controller Lab's Android side: the game controllers Android knows
/// (InputDevice: name, vendor/product id, axes, battery), their key
/// presses and stick/trigger motion, sent to Dart.
///   MethodChannel "controller_lab/input": devices, rumble
///   EventChannel  "controller_lab/events": {e: devices|key|motion, ...}
/// Every event still goes on to Flutter afterwards (for app navigation).
class MainActivity : FlutterActivity(), InputManager.InputDeviceListener {
    private var sink: EventChannel.EventSink? = null
    private val inputManager by lazy { getSystemService(Context.INPUT_SERVICE) as InputManager }

    // Same order as Dart's androidAxes.
    private val axes = intArrayOf(
        MotionEvent.AXIS_X, MotionEvent.AXIS_Y, MotionEvent.AXIS_Z, MotionEvent.AXIS_RZ,
        MotionEvent.AXIS_RX, MotionEvent.AXIS_RY, MotionEvent.AXIS_LTRIGGER,
        MotionEvent.AXIS_RTRIGGER, MotionEvent.AXIS_BRAKE, MotionEvent.AXIS_GAS,
        MotionEvent.AXIS_HAT_X, MotionEvent.AXIS_HAT_Y,
    )

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        val messenger = flutterEngine.dartExecutor.binaryMessenger
        MethodChannel(messenger, "controller_lab/input").setMethodCallHandler { call, result ->
            when (call.method) {
                "devices" -> result.success(devices())
                "rumble" -> result.success(
                    rumble(call.argument<Int>("id") ?: -1, call.argument<Int>("ms") ?: 300)
                )
                else -> result.notImplemented()
            }
        }
        EventChannel(messenger, "controller_lab/events").setStreamHandler(
            object : EventChannel.StreamHandler {
                override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                    sink = events
                    inputManager.registerInputDeviceListener(
                        this@MainActivity, Handler(Looper.getMainLooper())
                    )
                }

                override fun onCancel(arguments: Any?) {
                    inputManager.unregisterInputDeviceListener(this@MainActivity)
                    sink = null
                }
            }
        )
    }

    private fun isController(d: InputDevice): Boolean {
        val s = d.sources
        return (s and InputDevice.SOURCE_GAMEPAD) == InputDevice.SOURCE_GAMEPAD ||
            (s and InputDevice.SOURCE_JOYSTICK) == InputDevice.SOURCE_JOYSTICK
    }

    private fun devices(): List<Map<String, Any?>> {
        val out = mutableListOf<Map<String, Any?>>()
        for (id in inputManager.inputDeviceIds) {
            val d = inputManager.getInputDevice(id) ?: continue
            if (!isController(d) || d.isVirtual) continue
            val m = HashMap<String, Any?>()
            m["id"] = d.id
            m["name"] = d.name
            m["vendorId"] = d.vendorId
            m["productId"] = d.productId
            m["descriptor"] = d.descriptor
            m["controllerNumber"] = d.controllerNumber
            m["sources"] = d.sources
            m["gamepad"] = (d.sources and InputDevice.SOURCE_GAMEPAD) == InputDevice.SOURCE_GAMEPAD
            m["axes"] = d.motionRanges.map { it.axis }.distinct()
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) m["external"] = d.isExternal
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                val b = d.batteryState
                if (b.isPresent) {
                    m["battery"] = b.capacity // 0..1, or NaN
                    m["batteryStatus"] = b.status
                }
                m["vibrator"] = d.vibratorManager.vibratorIds.isNotEmpty()
            } else {
                @Suppress("DEPRECATION")
                val hasVibrator = d.vibrator.hasVibrator()
                m["vibrator"] = hasVibrator
            }
            out.add(m)
        }
        return out
    }

    @Suppress("DEPRECATION")
    private fun rumble(id: Int, ms: Int): Boolean {
        val d = inputManager.getInputDevice(id) ?: return false
        return try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                val vm = d.vibratorManager
                if (vm.vibratorIds.isEmpty()) return false
                vm.defaultVibrator.vibrate(
                    VibrationEffect.createOneShot(ms.toLong(), VibrationEffect.DEFAULT_AMPLITUDE)
                )
            } else {
                val v = d.vibrator
                if (!v.hasVibrator()) return false
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                    v.vibrate(VibrationEffect.createOneShot(ms.toLong(), VibrationEffect.DEFAULT_AMPLITUDE))
                } else {
                    v.vibrate(ms.toLong())
                }
            }
            true
        } catch (e: Exception) {
            false
        }
    }

    override fun dispatchKeyEvent(event: KeyEvent): Boolean {
        val d = event.device
        if (sink != null && d != null && isController(d) && event.repeatCount == 0) {
            sink?.success(
                mapOf(
                    "e" to "key", "id" to event.deviceId, "code" to event.keyCode,
                    "down" to (event.action == KeyEvent.ACTION_DOWN),
                )
            )
        }
        return super.dispatchKeyEvent(event)
    }

    override fun dispatchGenericMotionEvent(event: MotionEvent): Boolean {
        if (sink != null && (event.source and InputDevice.SOURCE_JOYSTICK) == InputDevice.SOURCE_JOYSTICK &&
            event.action == MotionEvent.ACTION_MOVE
        ) {
            sink?.success(
                mapOf(
                    "e" to "motion", "id" to event.deviceId,
                    "axes" to axes.map { event.getAxisValue(it).toDouble() },
                )
            )
        }
        return super.dispatchGenericMotionEvent(event)
    }

    override fun onInputDeviceAdded(deviceId: Int) {
        sink?.success(mapOf("e" to "devices"))
    }

    override fun onInputDeviceRemoved(deviceId: Int) {
        sink?.success(mapOf("e" to "devices"))
    }

    override fun onInputDeviceChanged(deviceId: Int) {
        sink?.success(mapOf("e" to "devices"))
    }
}
