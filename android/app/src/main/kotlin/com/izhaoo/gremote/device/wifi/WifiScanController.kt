package com.izhaoo.gremote.device.wifi

import android.Manifest
import android.app.Activity
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.content.pm.PackageManager
import android.location.LocationManager
import android.net.wifi.WifiManager
import android.os.Build
import android.os.Handler
import android.os.Looper
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel

/** Foreground discovery only: never connects to a network or handles credentials. */
class WifiScanController(private val activity: Activity, messenger: BinaryMessenger) {
    private val channel = MethodChannel(messenger, "gremote/wifi_scan")
    private val wifi = activity.applicationContext.getSystemService(Context.WIFI_SERVICE) as? WifiManager
    private val handler = Handler(Looper.getMainLooper())
    private val waiting = mutableListOf<MethodChannel.Result>()
    private var receiver: BroadcastReceiver? = null
    private var closed = false
    private val timeout = Runnable { complete(fresh = false) }

    init {
        channel.setMethodCallHandler { call, result ->
            if (call.method == "scan") scan(result) else result.notImplemented()
        }
    }

    @Suppress("DEPRECATION")
    private fun scan(result: MethodChannel.Result) {
        val error = availabilityError()
        if (error != null) {
            result.error(error, error, null)
            return
        }
        // Share one bounded scan when Flutter callers overlap.
        waiting.add(result)
        if (receiver != null) return
        val scanReceiver = object : BroadcastReceiver() {
            override fun onReceive(context: Context?, intent: Intent?) {
                if (receiver !== this || intent?.action != WifiManager.SCAN_RESULTS_AVAILABLE_ACTION) return
                // Read trusted WifiManager results; the broadcast carries no network data.
                complete(intent.getBooleanExtra(WifiManager.EXTRA_RESULTS_UPDATED, false))
            }
        }
        try {
            val filter = IntentFilter(WifiManager.SCAN_RESULTS_AVAILABLE_ACTION)
            // Some system broadcasts originate from privileged processes outside system UID.
            if (Build.VERSION.SDK_INT >= 33) {
                activity.registerReceiver(scanReceiver, filter, Context.RECEIVER_EXPORTED)
            } else {
                activity.registerReceiver(scanReceiver, filter)
            }
            receiver = scanReceiver
            handler.postDelayed(timeout, 7_000L)
            if (wifi?.startScan() != true) complete(fresh = false)
        } catch (_: SecurityException) {
            fail(availabilityError() ?: "locationPermissionDenied")
        } catch (_: Exception) {
            fail("wifiUnavailable")
        }
    }

    private fun availabilityError(): String? = when {
        closed || wifi == null -> "wifiUnavailable"
        !wifi.isWifiEnabled -> "wifiDisabled"
        activity.checkSelfPermission(Manifest.permission.ACCESS_FINE_LOCATION) != PackageManager.PERMISSION_GRANTED ->
            "locationPermissionDenied"
        !locationEnabled() -> "locationDisabled"
        else -> null
    }

    @Suppress("DEPRECATION")
    private fun locationEnabled(): Boolean {
        val location = activity.getSystemService(Context.LOCATION_SERVICE) as? LocationManager ?: return false
        return if (Build.VERSION.SDK_INT >= 28) location.isLocationEnabled else
            location.isProviderEnabled(LocationManager.GPS_PROVIDER) ||
                location.isProviderEnabled(LocationManager.NETWORK_PROVIDER)
    }

    @Suppress("DEPRECATION")
    private fun complete(fresh: Boolean) {
        if (waiting.isEmpty()) return
        val error = availabilityError()
        if (error != null) {
            fail(error)
            return
        }
        try {
            val networks = WifiScanNetworks.select(wifi!!.scanResults.map { WifiScanNetwork(it.SSID, it.level) })
            val response = mapOf(
                "networks" to networks.map { mapOf("ssid" to it.ssid, "rssi" to it.rssi) },
                "fresh" to fresh,
            )
            val results = drain()
            results.forEach { it.success(response) }
        } catch (_: SecurityException) {
            fail(availabilityError() ?: "locationPermissionDenied")
        } catch (_: Exception) {
            fail("wifiUnavailable")
        }
    }

    private fun fail(code: String) {
        drain().forEach { it.error(code, code, null) }
    }

    private fun drain(): List<MethodChannel.Result> {
        handler.removeCallbacks(timeout)
        receiver?.let { try { activity.unregisterReceiver(it) } catch (_: IllegalArgumentException) {} }
        receiver = null
        return waiting.toList().also { waiting.clear() }
    }

    fun onPause() {
        // Keep receivers foreground-only and return cached data if the app leaves the screen.
        complete(fresh = false)
    }

    fun close() {
        closed = true
        fail("wifiUnavailable")
        channel.setMethodCallHandler(null)
    }
}
