package com.izhaoo.gremote.device.ble

import android.annotation.SuppressLint
import android.bluetooth.BluetoothDevice
import android.bluetooth.BluetoothGatt
import android.bluetooth.BluetoothGattCallback
import android.bluetooth.BluetoothGattCharacteristic
import android.bluetooth.BluetoothGattDescriptor
import android.bluetooth.BluetoothManager
import android.bluetooth.BluetoothProfile
import android.bluetooth.le.ScanCallback
import android.bluetooth.le.ScanResult
import android.bluetooth.le.ScanSettings
import android.content.Context
import android.os.Build
import android.os.Handler
import android.os.Looper
import com.izhaoo.gremote.device.NativeBleDevice
import com.izhaoo.gremote.device.NativeCameraBootstrap
import java.util.UUID
import kotlin.coroutines.resume
import kotlin.coroutines.resumeWithException
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.TimeoutCancellationException
import kotlinx.coroutines.suspendCancellableCoroutine
import kotlinx.coroutines.withContext
import kotlinx.coroutines.withTimeout

class RicohBleException(val code: String, message: String) : Exception(message)

@SuppressLint("MissingPermission")
class RicohBleManager(
    context: Context,
    private val emitEvent: (String, String) -> Unit,
) {
    private val appContext = context.applicationContext
    private val bluetoothManager =
        appContext.getSystemService(BluetoothManager::class.java)
    private val adapter get() = bluetoothManager?.adapter
    private val mainHandler = Handler(Looper.getMainLooper())
    private val discoveryGate = GattDiscoveryGate()
    private var attempt = 0

    @Volatile private var gatt: BluetoothGatt? = null
    @Volatile private var operationQueue = GattOperationQueue()
    @Volatile private var connectResult: CompletableDeferred<Unit>? = null
    @Volatile private var descriptorResult: CompletableDeferred<UUID>? = null

    private val gattCallback = object : BluetoothGattCallback() {
        override fun onConnectionStateChange(
            gatt: BluetoothGatt,
            status: Int,
            newState: Int,
        ) {
            if (gatt !== this@RicohBleManager.gatt) return
            when (newState) {
                BluetoothProfile.STATE_CONNECTED -> {
                    emitTrace("connected", status)
                    emitEvent("bleState", "{\"state\":\"connected\"}")
                    val currentAttempt = attempt
                    if (!gatt.requestMtu(247)) discoverServices(gatt, currentAttempt)
                    else mainHandler.postDelayed({ discoverServices(gatt, currentAttempt) }, 1500)
                }
                BluetoothProfile.STATE_DISCONNECTED -> {
                    emitTrace("disconnected", status)
                    emitEvent(
                        "bleState",
                        "{\"state\":\"disconnected\",\"status\":$status}",
                    )
                    operationQueue.cancelAll()
                    connectResult?.completeExceptionally(
                        RicohBleException("bleDisconnected", "Camera disconnected"),
                    )
                    connectResult = null
                }
            }
        }

        override fun onMtuChanged(gatt: BluetoothGatt, mtu: Int, status: Int) {
            if (gatt !== this@RicohBleManager.gatt) return
            emitTrace("mtu", status)
            emitEvent("bleMtu", "{\"mtu\":$mtu,\"status\":$status}")
            discoverServices(gatt, attempt)
        }

        override fun onServicesDiscovered(gatt: BluetoothGatt, status: Int) {
            if (gatt !== this@RicohBleManager.gatt) return
            emitTrace("services", status)
            val completion = connectResult ?: return
            if (status != BluetoothGatt.GATT_SUCCESS) {
                completion.completeExceptionally(
                    RicohBleException("bleServiceDiscovery", "Service discovery failed: $status"),
                )
            } else if (gatt.findCharacteristic(RicohGattIds.MODEL) == null) {
                completion.completeExceptionally(
                    RicohBleException("unsupportedCamera", "GR model characteristic is absent"),
                )
            } else {
                completion.complete(Unit)
            }
            connectResult = null
        }

        @Deprecated("Used on Android 12 and below")
        override fun onCharacteristicRead(
            gatt: BluetoothGatt,
            characteristic: BluetoothGattCharacteristic,
            status: Int,
        ) {
            if (gatt !== this@RicohBleManager.gatt) return
            @Suppress("DEPRECATION")
            val value = characteristic.value ?: byteArrayOf()
            handleCharacteristicResult(characteristic.uuid, value, status)
        }

        override fun onCharacteristicRead(
            gatt: BluetoothGatt,
            characteristic: BluetoothGattCharacteristic,
            value: ByteArray,
            status: Int,
        ) {
            if (gatt !== this@RicohBleManager.gatt) return
            handleCharacteristicResult(characteristic.uuid, value, status)
        }

        override fun onCharacteristicWrite(
            gatt: BluetoothGatt,
            characteristic: BluetoothGattCharacteristic,
            status: Int,
        ) {
            if (gatt !== this@RicohBleManager.gatt) return
            handleCharacteristicResult(characteristic.uuid, byteArrayOf(), status)
        }

        @Deprecated("Used on Android 12 and below")
        override fun onCharacteristicChanged(
            gatt: BluetoothGatt,
            characteristic: BluetoothGattCharacteristic,
        ) {
            if (gatt !== this@RicohBleManager.gatt) return
            @Suppress("DEPRECATION")
            val value = characteristic.value ?: byteArrayOf()
            emitNotification(characteristic.uuid, value)
        }

        override fun onCharacteristicChanged(
            gatt: BluetoothGatt,
            characteristic: BluetoothGattCharacteristic,
            value: ByteArray,
        ) {
            if (gatt !== this@RicohBleManager.gatt) return
            emitNotification(characteristic.uuid, value)
        }

        override fun onDescriptorWrite(
            gatt: BluetoothGatt,
            descriptor: BluetoothGattDescriptor,
            status: Int,
        ) {
            if (gatt !== this@RicohBleManager.gatt) return
            val result = descriptorResult ?: return
            if (status == BluetoothGatt.GATT_SUCCESS) {
                result.complete(descriptor.characteristic.uuid)
            } else {
                result.completeExceptionally(
                    RicohBleException("bleNotifyFailed", "CCCD write failed: $status"),
                )
            }
            descriptorResult = null
        }
    }

    suspend fun scan(timeoutMs: Long): List<NativeBleDevice> =
        withContext(Dispatchers.Main.immediate) {
            val bluetoothAdapter = adapter
                ?: throw RicohBleException("bluetoothUnavailable", "Bluetooth adapter unavailable")
            if (!bluetoothAdapter.isEnabled) {
                throw RicohBleException("bluetoothDisabled", "Bluetooth is disabled")
            }

            suspendCancellableCoroutine { continuation ->
                val devices = linkedMapOf<String, NativeBleDevice>()
                var completed = false
                lateinit var callback: ScanCallback

                fun finish(error: Throwable? = null) {
                    if (completed) return
                    completed = true
                    bluetoothAdapter.bluetoothLeScanner?.stopScan(callback)
                    if (!continuation.isActive) return
                    if (error == null) {
                        continuation.resume(devices.values.sortedByDescending { it.rssi ?: Int.MIN_VALUE.toLong() })
                    } else {
                        continuation.resumeWithException(error)
                    }
                }

                callback = object : ScanCallback() {
                    override fun onScanResult(callbackType: Int, result: ScanResult) {
                        val advertisedServices =
                            result.scanRecord?.serviceUuids?.map { it.uuid }?.toSet().orEmpty()
                        val name = result.scanRecord?.deviceName.orEmpty()
                        val matchesService = advertisedServices.any(RicohGattIds.SCAN_SERVICES::contains)
                        val matchesName = name.startsWith("RICOH", ignoreCase = true)
                        if (!matchesService && !matchesName) return

                        val previous = devices[result.device.address]
                        if (previous == null || result.rssi > (previous.rssi ?: Int.MIN_VALUE.toLong())) {
                            devices[result.device.address] = NativeBleDevice(
                                id = result.device.address,
                                name = name.ifBlank { "RICOH Camera" },
                                rssi = result.rssi.toLong(),
                            )
                        }
                    }

                    override fun onScanFailed(errorCode: Int) {
                        finish(RicohBleException("bleScanFailed", "BLE scan failed: $errorCode"))
                    }
                }

                val settings = ScanSettings.Builder()
                    .setScanMode(ScanSettings.SCAN_MODE_LOW_LATENCY)
                    .build()
                val scanner = bluetoothAdapter.bluetoothLeScanner
                if (scanner == null) {
                    finish(RicohBleException("bluetoothUnavailable", "BLE scanner unavailable"))
                    return@suspendCancellableCoroutine
                }
                scanner.startScan(null, settings, callback)
                mainHandler.postDelayed({ finish() }, timeoutMs)
                continuation.invokeOnCancellation { mainHandler.post { finish() } }
            }
        }

    suspend fun connect(deviceId: String) = withContext(Dispatchers.Main.immediate) {
        disconnect()
        attempt = discoveryGate.begin()
        val bluetoothAdapter = adapter
            ?: throw RicohBleException("bluetoothUnavailable", "Bluetooth adapter unavailable")
        val device = try {
            bluetoothAdapter.getRemoteDevice(deviceId)
        } catch (error: IllegalArgumentException) {
            throw RicohBleException("invalidDevice", "Invalid BLE device identifier")
        }

        operationQueue = GattOperationQueue()
        val completion = CompletableDeferred<Unit>()
        connectResult = completion
        gatt = device.connectGatt(appContext, false, gattCallback, BluetoothDevice.TRANSPORT_LE)
        try {
            withTimeout(15_000) { completion.await() }
        } catch (error: TimeoutCancellationException) {
            emitTrace("connectTimeout")
            disconnect()
            throw RicohBleException("bleConnectTimeout", "Camera connection timed out")
        } catch (error: Throwable) {
            disconnect()
            throw error
        }
    }

    suspend fun readBootstrap(): NativeCameraBootstrap {
        emitTrace("readModel")
        val model = readString(RicohGattIds.MODEL)
        emitTrace("readFirmware")
        val firmware = readString(RicohGattIds.FIRMWARE)
        emitTrace("readBattery")
        val battery = read(RicohGattIds.BATTERY)
        emitTrace("batteryLength", battery.size)
        val batteryPayload = BatteryPayload.parse(battery)
        emitTrace("readSsid")
        val ssid = readString(RicohGattIds.SSID)
        emitTrace("readPassphrase")
        val passphrase = readString(RicohGattIds.PASSPHRASE)
        emitTrace("readComplete")

        enableNotificationIfAvailable(RicohGattIds.BATTERY)
        enableNotificationIfAvailable(RicohGattIds.CAPTURE_STATUS)

        return NativeCameraBootstrap(
            model = model,
            firmware = firmware,
            batteryLevel = batteryPayload.level.toLong(),
            acPowered = batteryPayload.acPowered,
            ssid = ssid,
            passphrase = passphrase,
        )
    }

    suspend fun setCameraPower(value: Int) = write(RicohGattIds.CAMERA_POWER, byteArrayOf(value.toByte()))

    suspend fun setNetworkType(value: Int) = write(RicohGattIds.NETWORK_TYPE, byteArrayOf(value.toByte()))

    suspend fun writeOperationRequest(value: ByteArray) = write(RicohGattIds.OPERATION_REQUEST, value)

    fun disconnect() {
        discoveryGate.invalidate()
        connectResult?.cancel()
        connectResult = null
        descriptorResult?.cancel()
        descriptorResult = null
        operationQueue.cancelAll()
        val oldGatt = gatt
        gatt = null
        oldGatt?.disconnect()
        oldGatt?.close()
    }

    private fun discoverServices(target: BluetoothGatt, currentAttempt: Int) {
        if (target !== gatt || !discoveryGate.shouldDiscover(currentAttempt)) return
        if (!target.discoverServices()) {
            connectResult?.completeExceptionally(
                RicohBleException("bleServiceDiscovery", "Android rejected service discovery"),
            )
            connectResult = null
        }
    }

    private fun emitTrace(phase: String, status: Int? = null) {
        val suffix = if (status == null) "" else ",\"status\":$status"
        emitEvent("bleTrace", "{\"phase\":\"$phase\"$suffix}")
    }

    private suspend fun readString(id: UUID): String {
        val bytes = read(id)
        val end = bytes.indexOfLast { it != 0.toByte() } + 1
        val content = bytes.copyOfRange(0, end)
        if (content.any { it == 0.toByte() }) {
            throw RicohBleException("invalidPayload", "Embedded NUL in BLE string")
        }
        return content.toString(Charsets.UTF_8)
    }

    private suspend fun read(id: UUID): ByteArray {
        val connectedGatt = requireGatt()
        val characteristic = connectedGatt.findCharacteristic(id)
            ?: throw RicohBleException("unsupported", "Characteristic $id is absent")
        return operationQueue.execute(id) { connectedGatt.readCharacteristic(characteristic) }
    }

    private suspend fun write(id: UUID, value: ByteArray) {
        val connectedGatt = requireGatt()
        val characteristic = connectedGatt.findCharacteristic(id)
            ?: throw RicohBleException("unsupported", "Characteristic $id is absent")
        operationQueue.execute(id) {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                connectedGatt.writeCharacteristic(
                    characteristic,
                    value,
                    BluetoothGattCharacteristic.WRITE_TYPE_DEFAULT,
                ) == BluetoothGatt.GATT_SUCCESS
            } else {
                @Suppress("DEPRECATION")
                characteristic.value = value
                @Suppress("DEPRECATION")
                connectedGatt.writeCharacteristic(characteristic)
            }
        }
    }

    private suspend fun enableNotificationIfAvailable(id: UUID) {
        val connectedGatt = requireGatt()
        val characteristic = connectedGatt.findCharacteristic(id) ?: return
        val descriptor = characteristic.getDescriptor(RicohGattIds.CLIENT_CHARACTERISTIC_CONFIG)
            ?: return
        if (!connectedGatt.setCharacteristicNotification(characteristic, true)) return

        val completion = CompletableDeferred<UUID>()
        descriptorResult = completion
        val started = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            connectedGatt.writeDescriptor(
                descriptor,
                BluetoothGattDescriptor.ENABLE_NOTIFICATION_VALUE,
            ) == BluetoothGatt.GATT_SUCCESS
        } else {
            @Suppress("DEPRECATION")
            descriptor.value = BluetoothGattDescriptor.ENABLE_NOTIFICATION_VALUE
            @Suppress("DEPRECATION")
            connectedGatt.writeDescriptor(descriptor)
        }
        if (!started) {
            descriptorResult = null
            return
        }
        try {
            withTimeout(8_000) { completion.await() }
        } catch (_: Throwable) {
            descriptorResult = null
            emitEvent("bleNotification", "{\"state\":\"unavailable\"}")
        }
    }

    private fun requireGatt(): BluetoothGatt =
        gatt ?: throw RicohBleException("bleDisconnected", "Camera is not connected")

    private fun handleCharacteristicResult(id: UUID, value: ByteArray, status: Int) {
        if (status == BluetoothGatt.GATT_SUCCESS) {
            operationQueue.complete(id, value)
        } else {
            emitTrace("operationFailure", status)
            operationQueue.fail(id, "bleGattError", "GATT status $status for $id")
        }
    }

    private fun emitNotification(id: UUID, value: ByteArray) {
        val hex = value.joinToString("") { "%02x".format(it) }
        emitEvent("bleNotify", "{\"uuid\":\"$id\",\"hex\":\"$hex\"}")
    }

    private fun BluetoothGatt.findCharacteristic(id: UUID): BluetoothGattCharacteristic? =
        services.asSequence().mapNotNull { it.getCharacteristic(id) }.firstOrNull()
}
