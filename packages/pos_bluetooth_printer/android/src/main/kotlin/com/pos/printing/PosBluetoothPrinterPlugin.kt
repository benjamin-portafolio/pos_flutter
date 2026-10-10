package com.pos.printing

import android.Manifest
import android.app.Activity
import android.bluetooth.BluetoothAdapter
import android.bluetooth.BluetoothManager
import android.content.Context
import android.content.pm.PackageManager
import android.os.Build
import android.os.Handler
import android.os.Looper
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.embedding.engine.plugins.activity.ActivityAware
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.PluginRegistry
import java.util.UUID
import java.util.concurrent.CompletableFuture
import java.util.concurrent.CompletionException

/** Android only, paired devices only. No discovery/auto enable/background service.
 * Channel registration does not touch Bluetooth or ask for permissions. */
class PosBluetoothPrinterPlugin : FlutterPlugin, MethodChannel.MethodCallHandler,
    ActivityAware, PluginRegistry.RequestPermissionsResultListener {
    private lateinit var context: Context
    private lateinit var channel: MethodChannel
    private val main = Handler(Looper.getMainLooper())
    private var activity: Activity? = null
    private var activityBinding: ActivityPluginBinding? = null
    private var transport: PrinterTransport? = null
    private var permissionRequest: PrinterPermissionRequest? = null
    private var permissionDeadline: Runnable? = null

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        context = binding.applicationContext
        channel = MethodChannel(binding.binaryMessenger, "pos/bluetooth_printer")
        channel.setMethodCallHandler(this)
    }

    private fun adapter(): BluetoothAdapter? =
        (context.getSystemService(Context.BLUETOOTH_SERVICE) as? BluetoothManager)?.adapter

    private fun granted(): Boolean = Build.VERSION.SDK_INT < 31 ||
        context.checkSelfPermission(Manifest.permission.BLUETOOTH_CONNECT) == PackageManager.PERMISSION_GRANTED

    private fun permissionStatus(): String {
        val requested = context.getSharedPreferences("pos_printer_permissions", Context.MODE_PRIVATE)
            .getBoolean("connect_requested", false)
        val rationale = if (Build.VERSION.SDK_INT >= 31)
            activity?.shouldShowRequestPermissionRationale(Manifest.permission.BLUETOOTH_CONNECT) ?: true
            else false
        return PrinterPermissionPolicy.status(Build.VERSION.SDK_INT, granted(), requested, rationale)
    }

    private fun requireReady(): BluetoothAdapter {
        val adapter = adapter() ?: throw TransportFailure("no_hardware")
        if (!granted()) throw TransportFailure("permission_denied")
        if (!adapter.isEnabled) throw TransportFailure("bluetooth_off")
        return adapter
    }

    private fun io(): PrinterTransport {
        transport?.let { return it }
        return PrinterTransport { address ->
            val adapter = requireReady()
            val device = adapter.bondedDevices.firstOrNull { it.address.equals(address, true) }
                ?: throw TransportFailure("device_not_bonded")
            val socket = device.createRfcommSocketToServiceRecord(
                UUID.fromString("00001101-0000-1000-8000-00805f9b34fb"))
            object : PrinterSocket {
                override fun connect() = socket.connect()
                override fun write(bytes: ByteArray, offset: Int, count: Int) {
                    requireReady() // Detect permission revocation before each band.
                    socket.outputStream.write(bytes, offset, count)
                }
                override fun flush() = socket.outputStream.flush()
                override fun close() = socket.close() // No flush during abort.
            }
        }.also { transport = it }
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        try {
            when (call.method) {
                "availability" -> result.success(when {
                    adapter() == null -> "no_hardware"
                    !granted() -> "permission_required"
                    adapter()?.isEnabled != true -> "off"
                    else -> "ready"
                })
                "permissionStatus" -> result.success(permissionStatus())
                "requestPermission" -> requestPermission(result)
                "bondedDevices" -> result.success(requireReady().bondedDevices.map {
                    mapOf("address" to it.address, "name" to it.name)
                }.sortedBy { it["address"] })
                "connect" -> {
                    requireReady()
                    val address = call.arguments as? String
                    if (address == null || !BluetoothAdapter.checkBluetoothAddress(address)) {
                        throw TransportFailure("device_not_bonded")
                    }
                    reply(io().connect(address), result, "connection_failed")
                }
                "write" -> {
                    requireReady()
                    val bytes = call.arguments as? ByteArray
                        ?: throw TransportFailure("write_failed")
                    if (bytes.isEmpty()) throw TransportFailure("write_failed")
                    reply(io().write(bytes), result, "write_failed")
                }
                "close" -> {
                    val current = transport
                    if (current == null) result.success(null)
                    else reply(current.close(), result, "close_failed")
                }
                else -> result.notImplemented()
            }
        } catch (error: SecurityException) {
            result.error("permission_denied", "Bluetooth permission revoked", null)
        } catch (error: TransportFailure) {
            result.error(error.code, error.code, null)
        } catch (error: Exception) {
            result.error("transport_error", error.javaClass.simpleName, null)
        }
    }

    private fun reply(future: CompletableFuture<Unit>, result: MethodChannel.Result,
                      fallback: String) {
        future.whenComplete { _, error ->
            main.post {
                if (error == null) result.success(null)
                else {
                    val cause = if (error is CompletionException) error.cause else error
                    val code = when (cause) {
                        is TransportFailure -> cause.code
                        is SecurityException -> "permission_denied"
                        else -> fallback
                    }
                    result.error(code, code, null)
                }
            }
        }
    }

    private fun requestPermission(result: MethodChannel.Result) {
        if (adapter() == null) throw TransportFailure("no_hardware")
        if (permissionRequest != null) throw TransportFailure("busy")
        if (granted()) { result.success("granted"); return }
        val current = activity ?: throw TransportFailure("permission_denied")
        if (permissionStatus() == "permanently_denied") {
            result.success("permanently_denied"); return
        }
        val request = PrinterPermissionRequest()
        permissionRequest = request
        request.future.whenComplete { status, error ->
            if (error == null) result.success(status)
            else result.error("timeout", "Permission request timed out", null)
        }
        context.getSharedPreferences("pos_printer_permissions", Context.MODE_PRIVATE)
            .edit().putBoolean("connect_requested", true).apply()
        val deadline = Runnable { request.expire() }
        permissionDeadline = deadline
        main.postDelayed(deadline, 30_000)
        try {
            current.requestPermissions(arrayOf(Manifest.permission.BLUETOOTH_CONNECT), REQUEST_CODE)
        } catch (error: Exception) {
            finishPermission("denied")
        }
    }

    override fun onRequestPermissionsResult(requestCode: Int, permissions: Array<out String>,
                                            grantResults: IntArray): Boolean {
        if (requestCode != REQUEST_CODE || permissionRequest == null) return false
        finishPermission(if (grantResults.isEmpty()) "denied" else permissionStatus())
        return true
    }

    private fun finishPermission(status: String) {
        permissionDeadline?.let { main.removeCallbacks(it) }
        permissionDeadline = null
        val request = permissionRequest
        permissionRequest = null
        request?.finish(status)
    }

    override fun onAttachedToActivity(binding: ActivityPluginBinding) {
        activityBinding = binding
        activity = binding.activity
        binding.addRequestPermissionsResultListener(this)
    }
    private fun detachActivity(finishPending: Boolean = true) {
        if (finishPending) finishPermission("denied")
        activityBinding?.removeRequestPermissionsResultListener(this)
        activityBinding = null
        activity = null
    }
    // Rotation replaces the Activity without necessarily dismissing its dialog.
    override fun onDetachedFromActivityForConfigChanges() = detachActivity(false)
    override fun onReattachedToActivityForConfigChanges(binding: ActivityPluginBinding) = onAttachedToActivity(binding)
    override fun onDetachedFromActivity() = detachActivity()
    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        finishPermission("denied")
        channel.setMethodCallHandler(null)
        transport?.shutdown()
        transport = null
    }
    companion object { private const val REQUEST_CODE = 8051 }
}
