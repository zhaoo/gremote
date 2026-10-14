package com.izhaoo.gremote.device.wifi

import android.annotation.SuppressLint
import android.content.Context
import android.net.ConnectivityManager
import android.net.Network
import android.net.NetworkCapabilities
import android.net.NetworkRequest
import android.net.wifi.WifiNetworkSpecifier
import java.util.concurrent.CancellationException
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

    private class Registration(
        val callback: ConnectivityManager.NetworkCallback,
        val attempt: NetworkRequestLifecycle.Attempt<Network>,
    )

    private val lifecycle = NetworkRequestLifecycle<Network>()
    @Volatile private var activeRegistration: Registration? = null

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
        val registration = synchronized(stateLock) {
            val attempt = lifecycle.begin()
            val callback = object : ConnectivityManager.NetworkCallback() {
                override fun onAvailable(network: Network) {
                    lifecycle.available(attempt, network) {
                        emitEvent("wifiState", "{\"state\":\"available\"}")
                    }
                }

                override fun onUnavailable() {
                    lifecycle.unavailable(
                        attempt,
                        CameraNetworkException(
                            code = "wifiUserRejected",
                            message = "Camera Wi-Fi request was rejected or unavailable",
                        ),
                    )
                }

                override fun onLost(network: Network) {
                    lifecycle.lost(attempt, network) {
                        onNetworkLost()
                        emitEvent("wifiState", "{\"state\":\"lost\"}")
                    }
                }
            }
            Registration(callback, attempt).also { activeRegistration = it }
        }
        try {
            synchronized(stateLock) {
                if (activeRegistration !== registration) {
                    throw CancellationException("Camera Wi-Fi request was cancelled")
                }
                connectivityManager.requestNetwork(request, registration.callback)
            }
            return withTimeout(timeoutMs) { registration.attempt.result.await() }
        } catch (error: TimeoutCancellationException) {
            unregister(registration)
            throw CameraNetworkException(
                code = "wifiTimeout",
                message = "Camera Wi-Fi request timed out",
                cause = error,
            )
        } catch (error: CancellationException) {
            unregister(registration)
            throw error
        } catch (error: Throwable) {
            unregister(registration)
            throw error
        }
    }

    fun disconnect() {
        val registration = synchronized(stateLock) {
            activeRegistration.also {
                activeRegistration = null
                it?.let { lifecycle.end(it.attempt) }
            }
        }
        registration?.let(::unregister)
    }

    private fun unregister(registration: Registration) {
        synchronized(stateLock) {
            if (activeRegistration === registration) activeRegistration = null
            lifecycle.end(registration.attempt)
        }
        runCatching { connectivityManager.unregisterNetworkCallback(registration.callback) }
    }
}
