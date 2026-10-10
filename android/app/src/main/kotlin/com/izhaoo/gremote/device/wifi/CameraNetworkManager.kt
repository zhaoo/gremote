package com.izhaoo.gremote.device.wifi

import android.annotation.SuppressLint
import android.content.Context
import android.net.ConnectivityManager
import android.net.Network
import android.net.NetworkCapabilities
import android.net.NetworkRequest
import android.net.wifi.WifiNetworkSpecifier
import java.util.concurrent.CancellationException
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.TimeoutCancellationException
import kotlinx.coroutines.withTimeout

class CameraNetworkException(
    val code: String,
    message: String,
    cause: Throwable? = null,
) : Exception(message, cause)

@SuppressLint("MissingPermission")
class CameraNetworkManager(
    context: Context,
    private val emitEvent: (String, String) -> Unit,
    private val onNetworkLost: () -> Unit,
    private val timeoutMs: Long = 30_000,
) {
    private val connectivityManager =
        context.applicationContext.getSystemService(ConnectivityManager::class.java)
    private val stateLock = Any()

    @Volatile private var activeCallback: ConnectivityManager.NetworkCallback? = null
    @Volatile private var activeNetwork: Network? = null

    suspend fun connect(ssid: String, passphrase: String): Network {
        require(ssid.isNotBlank()) { "Camera SSID must not be blank" }
        require(passphrase.isNotBlank()) { "Camera passphrase must not be blank" }
        disconnect()

        val specifier = WifiNetworkSpecifier.Builder()
            .setSsid(ssid)
            .setWpa2Passphrase(passphrase)
            .build()
        val request = NetworkRequest.Builder()
            .addTransportType(NetworkCapabilities.TRANSPORT_WIFI)
            .removeCapability(NetworkCapabilities.NET_CAPABILITY_INTERNET)
            .setNetworkSpecifier(specifier)
            .build()
        val result = CompletableDeferred<Network>()
        val callback = object : ConnectivityManager.NetworkCallback() {
            override fun onAvailable(network: Network) {
                activeNetwork = network
                result.complete(network)
                emitEvent("wifiState", "{\"state\":\"available\"}")
            }

            override fun onUnavailable() {
                result.completeExceptionally(
                    CameraNetworkException(
                        code = "wifiUserRejected",
                        message = "Camera Wi-Fi request was rejected or unavailable",
                    ),
                )
            }

            override fun onLost(network: Network) {
                if (activeNetwork != network) return
                activeNetwork = null
                onNetworkLost()
                emitEvent("wifiState", "{\"state\":\"lost\"}")
            }
        }

        synchronized(stateLock) { activeCallback = callback }
        try {
            connectivityManager.requestNetwork(request, callback)
            return withTimeout(timeoutMs) { result.await() }
        } catch (error: TimeoutCancellationException) {
            unregister(callback)
            throw CameraNetworkException(
                code = "wifiTimeout",
                message = "Camera Wi-Fi request timed out",
                cause = error,
            )
        } catch (error: CancellationException) {
            unregister(callback)
            throw error
        } catch (error: Throwable) {
            unregister(callback)
            throw error
        }
    }

    fun disconnect() {
        val callback = synchronized(stateLock) {
            activeCallback.also { activeCallback = null }
        }
        activeNetwork = null
        callback?.let(::unregister)
    }

    private fun unregister(callback: ConnectivityManager.NetworkCallback) {
        synchronized(stateLock) {
            if (activeCallback === callback) activeCallback = null
        }
        runCatching { connectivityManager.unregisterNetworkCallback(callback) }
    }
}
