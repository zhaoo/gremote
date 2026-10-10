package com.izhaoo.gremote

import android.view.WindowManager
import com.izhaoo.gremote.device.CameraDeviceFlutterApi
import com.izhaoo.gremote.device.CameraDeviceHostApi
import com.izhaoo.gremote.device.GRemoteDeviceHostApi
import com.izhaoo.gremote.media.GRemoteMediaHostApi
import com.izhaoo.gremote.media.MediaHostApi
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine

class MainActivity : FlutterActivity() {
    private var deviceApi: GRemoteDeviceHostApi? = null
    private var mediaApi: GRemoteMediaHostApi? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        val messenger = flutterEngine.dartExecutor.binaryMessenger
        deviceApi = GRemoteDeviceHostApi(
            context = applicationContext,
            flutterApi = CameraDeviceFlutterApi(messenger),
            keepScreenOn = ::setKeepScreenOn,
        ).also { CameraDeviceHostApi.setUp(messenger, it) }
        mediaApi = GRemoteMediaHostApi(this).also { MediaHostApi.setUp(messenger, it) }
    }

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray,
    ) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        mediaApi?.onRequestPermissionsResult(requestCode)
    }

    private fun setKeepScreenOn(on: Boolean) = runOnUiThread {
        if (on) {
            window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
        } else {
            window.clearFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
        }
    }

    override fun cleanUpFlutterEngine(flutterEngine: FlutterEngine) {
        val messenger = flutterEngine.dartExecutor.binaryMessenger
        CameraDeviceHostApi.setUp(messenger, null)
        MediaHostApi.setUp(messenger, null)
        deviceApi?.close()
        deviceApi = null
        mediaApi?.close()
        mediaApi = null
        super.cleanUpFlutterEngine(flutterEngine)
    }
}
