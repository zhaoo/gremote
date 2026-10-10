package com.izhaoo.gremote.device

import android.content.Context
import android.os.Build
import com.izhaoo.gremote.device.ble.GattOperationException
import com.izhaoo.gremote.device.ble.RicohBleException
import com.izhaoo.gremote.device.ble.RicohBleManager
import com.izhaoo.gremote.device.http.BoundCameraTransport
import com.izhaoo.gremote.device.http.CameraTransportException
import com.izhaoo.gremote.device.wifi.CameraNetworkException
import com.izhaoo.gremote.device.wifi.CameraNetworkManager
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.launch

class GRemoteDeviceHostApi(
    context: Context,
    private val flutterApi: CameraDeviceFlutterApi,
    private val keepScreenOn: (Boolean) -> Unit,
) : CameraDeviceHostApi {
    private val appContext = context.applicationContext
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Main.immediate)
    private val ble = RicohBleManager(context, ::emitNativeEvent)
    @Volatile private var transport: BoundCameraTransport? = null
    private val networkManager = CameraNetworkManager(
        context = context,
        emitEvent = ::emitNativeEvent,
        onNetworkLost = {
            transport?.stopLiveView()
            transport?.closeChangeSocket()
        },
    )

    override fun androidSdkInt(): Long = Build.VERSION.SDK_INT.toLong()

    override fun scan(timeoutMs: Long, callback: (Result<List<NativeBleDevice?>>) -> Unit) =
        launchResult(callback) { ble.scan(timeoutMs).map { it } }

    override fun connectBle(deviceId: String, callback: (Result<Unit>) -> Unit) =
        launchResult(callback) { ble.connect(deviceId) }

    override fun disconnectBle(callback: (Result<Unit>) -> Unit) =
        launchResult(callback) {
            transport?.close()
            transport = null
            networkManager.disconnect()
            ble.disconnect()
        }

    override fun readBootstrap(callback: (Result<NativeCameraBootstrap>) -> Unit) =
        launchResult(callback) { ble.readBootstrap() }

    override fun setCameraPower(value: Long, callback: (Result<Unit>) -> Unit) =
        launchResult(callback) {
            require(value in 0L..2L) { "Camera power must be 0..2" }
            ble.setCameraPower(value.toInt())
        }

    override fun setNetworkType(value: Long, callback: (Result<Unit>) -> Unit) =
        launchResult(callback) {
            require(value in 0L..1L) { "Network type must be 0..1" }
            ble.setNetworkType(value.toInt())
        }

    override fun writeOperationRequest(value: ByteArray, callback: (Result<Unit>) -> Unit) =
        launchResult(callback) {
            require(value.size == 2) { "Operation request must contain 2 bytes" }
            ble.writeOperationRequest(value)
        }

    override fun connectCameraWifi(
        ssid: String,
        passphrase: String,
        callback: (Result<Unit>) -> Unit,
    ) = launchResult(callback) {
        transport?.close()
        transport = null
        val network = networkManager.connect(ssid, passphrase)
        val candidate = BoundCameraTransport(
            network = network,
            context = appContext,
            onLiveViewChunk = ::emitLiveViewChunk,
            emitEvent = ::emitNativeEvent,
        )
        try {
            candidate.probeCamera()
            transport = candidate
        } catch (error: Throwable) {
            candidate.close()
            networkManager.disconnect()
            throw error
        }
    }

    override fun cameraRequest(
        method: String,
        url: String,
        headers: Map<String?, String?>,
        body: ByteArray?,
        callback: (Result<NativeHttpResponse>) -> Unit,
    ) = launchResult(callback) {
        val safeHeaders = headers.entries.mapNotNull { (key, value) ->
            if (key == null || value == null) null else key to value
        }.toMap()
        requireTransport().request(method, url, safeHeaders, body)
    }

    override fun downloadPhoto(
        directory: String,
        fileName: String,
        callback: (Result<String>) -> Unit,
    ) = launchResult(callback) { requireTransport().downloadPhoto(directory, fileName) }

    override fun startLiveView(url: String, callback: (Result<Unit>) -> Unit) =
        launchResult(callback) { requireTransport().startLiveView(url) }

    override fun stopLiveView(callback: (Result<Unit>) -> Unit) =
        launchResult(callback) { transport?.stopLiveView() }

    override fun openChangeSocket(path: String, callback: (Result<Unit>) -> Unit) =
        launchResult(callback) { requireTransport().openChangeSocket(path) }

    override fun closeChangeSocket(callback: (Result<Unit>) -> Unit) =
        launchResult(callback) { transport?.closeChangeSocket() }

    override fun setKeepScreenOn(on: Boolean) = keepScreenOn(on)

    fun close() {
        transport?.close()
        transport = null
        networkManager.disconnect()
        ble.disconnect()
        scope.cancel()
    }

    private fun emitNativeEvent(type: String, payload: String) {
        scope.launch { flutterApi.onNativeEvent(type, payload) { } }
    }

    private fun emitLiveViewChunk(bytes: ByteArray) {
        scope.launch { flutterApi.onLiveViewChunk(bytes) { } }
    }

    private fun requireTransport(): BoundCameraTransport =
        transport ?: throw CameraTransportException(
            code = "wifiNotConnected",
            message = "Camera Wi-Fi is not connected",
        )

    private fun <T> launchResult(callback: (Result<T>) -> Unit, block: suspend () -> T) {
        scope.launch {
            callback(
                try {
                    Result.success(block())
                } catch (error: Throwable) {
                    Result.failure(error.asFlutterError())
                },
            )
        }
    }

    private fun Throwable.asFlutterError(): FlutterError = when (this) {
        is FlutterError -> this
        is RicohBleException -> FlutterError(code, message)
        is GattOperationException -> FlutterError(code, message)
        is CameraNetworkException -> FlutterError(code, message)
        is CameraTransportException -> FlutterError(code, message)
        is SecurityException -> FlutterError("permissionDenied", message)
        is IllegalArgumentException -> FlutterError("invalidArgument", message)
        else -> FlutterError("nativeFailure", message ?: javaClass.simpleName)
    }
}
