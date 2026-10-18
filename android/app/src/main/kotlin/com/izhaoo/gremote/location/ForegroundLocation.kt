package com.izhaoo.gremote.location

import android.Manifest
import android.annotation.SuppressLint
import android.content.Context
import android.content.pm.PackageManager
import android.location.Location
import android.location.LocationListener
import android.location.LocationManager
import android.os.Bundle
import android.os.Looper
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel

/** Foreground-only location. No service, background permission, logs or camera writes. */
class ForegroundLocation(context: Context, messenger: BinaryMessenger) {
    private val context = context.applicationContext
    private val manager = context.getSystemService(LocationManager::class.java)
    private val channel = MethodChannel(messenger, "gremote/location")
    private val events = EventChannel(messenger, "gremote/location/fixes")
    private var sink: EventChannel.EventSink? = null
    private var running = false
    private var resumed = false
    private val listener = object : LocationListener {
        override fun onLocationChanged(location: Location) { send(location) }
        override fun onProviderEnabled(provider: String) {}
        override fun onProviderDisabled(provider: String) {
            if (running && providers().isEmpty()) {
                sink?.error("locationDisabled", "Phone location is disabled", null)
                stop()
            }
        }
        @Deprecated("Legacy callback")
        override fun onStatusChanged(provider: String?, status: Int, extras: Bundle?) {}
    }
    init {
        events.setStreamHandler(object : EventChannel.StreamHandler {
            override fun onListen(arguments: Any?, eventSink: EventChannel.EventSink) { sink = eventSink }
            override fun onCancel(arguments: Any?) { stop(); sink = null }
        })
        channel.setMethodCallHandler { call, result ->
            when (call.method) {
                "start" -> try { start(); result.success(null) } catch (_: SecurityException) {
                    stop(); result.error("permissionDenied", "Location permission required", null)
                } catch (_: Exception) {
                    stop(); result.error("locationDisabled", "Phone location is unavailable", null)
                }
                "stop" -> { stop(); result.success(null) }
                else -> result.notImplemented()
            }
        }
    }
    private fun providers() = listOf(LocationManager.GPS_PROVIDER, LocationManager.NETWORK_PROVIDER)
        .filter { manager.isProviderEnabled(it) }

    @SuppressLint("MissingPermission")
    private fun start() {
        check(resumed) { "Activity is not resumed" }
        if (running) return
        val fine = context.checkSelfPermission(Manifest.permission.ACCESS_FINE_LOCATION) == PackageManager.PERMISSION_GRANTED
        val coarse = context.checkSelfPermission(Manifest.permission.ACCESS_COARSE_LOCATION) == PackageManager.PERMISSION_GRANTED
        if (!fine && !coarse) throw SecurityException()
        val available = providers()
        check(available.isNotEmpty()) { "Location providers disabled" }
        running = true
        available.forEach { provider ->
            manager.requestLocationUpdates(provider, 5000L, 5f, listener, Looper.getMainLooper())
        }
        // Deliver asynchronously so Dart has acknowledged start before its first sample.
        android.os.Handler(Looper.getMainLooper()).post {
            if (running) available.mapNotNull { runCatching { manager.getLastKnownLocation(it) }.getOrNull() }
                .maxByOrNull { it.time }?.let(::send)
        }
    }
    private fun send(location: Location) {
        if (!running || !location.hasAccuracy()) return
        sink?.success(mapOf("latitude" to location.latitude, "longitude" to location.longitude,
            "accuracy" to location.accuracy.toDouble(), "timestamp" to location.time,
            "altitude" to if (location.hasAltitude()) location.altitude else null))
    }
    fun onResume() { resumed = true }
    fun onPause() { resumed = false; stop() }
    fun stop() {
        running = false
        runCatching { manager.removeUpdates(listener) }
    }
    fun close() {
        stop()
        channel.setMethodCallHandler(null)
        events.setStreamHandler(null)
        sink = null
    }
}
