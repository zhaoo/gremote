package com.izhaoo.gremote.media

import android.Manifest
import android.app.Activity
import android.content.pm.PackageManager
import android.os.Build

/** Photo-library runtime permissions, resolved per Android version. */
class MediaPermissions(private val activity: Activity) {
    private val pending = mutableMapOf<Int, () -> Unit>()

    fun access(): NativeMediaAccess = when {
        fullAccessPermissions().all(::granted) -> NativeMediaAccess.GRANTED
        Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE &&
            granted(Manifest.permission.READ_MEDIA_VISUAL_USER_SELECTED) -> NativeMediaAccess.PARTIAL
        else -> NativeMediaAccess.DENIED
    }

    /** Without ACCESS_MEDIA_LOCATION the system redacts EXIF GPS on Android 10+. */
    fun hasLocationAccess(): Boolean =
        Build.VERSION.SDK_INT < Build.VERSION_CODES.Q ||
            granted(Manifest.permission.ACCESS_MEDIA_LOCATION)

    fun requestAccess(done: (NativeMediaAccess) -> Unit) {
        val requested = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
            fullAccessPermissions() + Manifest.permission.READ_MEDIA_VISUAL_USER_SELECTED
        } else {
            fullAccessPermissions()
        }
        request(REQUEST_MEDIA, requested) { done(access()) }
    }

    fun requestLocationAccess(done: (Boolean) -> Unit) {
        if (hasLocationAccess()) {
            done(true)
            return
        }
        request(REQUEST_LOCATION, arrayOf(Manifest.permission.ACCESS_MEDIA_LOCATION)) {
            done(hasLocationAccess())
        }
    }

    /** Returns true when [requestCode] belonged to this helper. */
    fun onRequestPermissionsResult(requestCode: Int): Boolean {
        val callback = pending.remove(requestCode) ?: return false
        callback()
        return true
    }

    private fun request(code: Int, permissions: Array<String>, callback: () -> Unit) {
        // A newer request supersedes an unanswered one; settle the old caller first.
        pending.put(code, callback)?.invoke()
        activity.requestPermissions(permissions, code)
    }

    private fun fullAccessPermissions(): Array<String> = when {
        Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU ->
            arrayOf(Manifest.permission.READ_MEDIA_IMAGES)
        Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q ->
            arrayOf(Manifest.permission.READ_EXTERNAL_STORAGE)
        else -> arrayOf(
            Manifest.permission.READ_EXTERNAL_STORAGE,
            Manifest.permission.WRITE_EXTERNAL_STORAGE,
        )
    }

    private fun granted(permission: String): Boolean =
        activity.checkSelfPermission(permission) == PackageManager.PERMISSION_GRANTED

    private companion object {
        const val REQUEST_MEDIA = 0x6D10
        const val REQUEST_LOCATION = 0x6D11
    }
}
