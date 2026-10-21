package com.izhaoo.gremote

import android.view.WindowManager
import android.content.Intent
import android.app.Activity
import com.izhaoo.gremote.device.FlutterError
import com.izhaoo.gremote.location.ForegroundLocation
import com.izhaoo.gremote.device.wifi.WifiScanController
import com.izhaoo.gremote.device.CameraDeviceFlutterApi
import com.izhaoo.gremote.device.CameraDeviceHostApi
import com.izhaoo.gremote.device.GRemoteDeviceHostApi
import com.izhaoo.gremote.media.GRemoteMediaHostApi
import com.izhaoo.gremote.media.MediaHostApi
import com.izhaoo.gremote.media.CameraImportHistory
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine

class MainActivity : FlutterActivity() {
    private var companionFileResult: ((Result<ByteArray?>) -> Unit)? = null
    private var companionFileLimit = 0
    private var location: ForegroundLocation? = null
    private var wifiScanController: WifiScanController? = null
    private var deviceApi: GRemoteDeviceHostApi? = null
    private var mediaApi: GRemoteMediaHostApi? = null
    private var importHistory: CameraImportHistory? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        val messenger = flutterEngine.dartExecutor.binaryMessenger
        wifiScanController = WifiScanController(this, messenger)
        location = ForegroundLocation(this, messenger)
        deviceApi = GRemoteDeviceHostApi(
            context = applicationContext,
            flutterApi = CameraDeviceFlutterApi(messenger),
            keepScreenOn = ::setKeepScreenOn,
            pickFile = ::pickCompanionFile,
        ).also { CameraDeviceHostApi.setUp(messenger, it) }
        mediaApi = GRemoteMediaHostApi(this).also { MediaHostApi.setUp(messenger, it) }
        importHistory = CameraImportHistory(applicationContext, messenger)
    }

    override fun onResume() {
        super.onResume()
        location?.onResume()
    }

    override fun onPause() {
        location?.onPause()
        wifiScanController?.onPause()
        super.onPause()
    }

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray,
    ) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        mediaApi?.onRequestPermissionsResult(requestCode)
    }

    private fun pickCompanionFile(kind: String, callback: (Result<ByteArray?>) -> Unit) {
        if (kind !in setOf("pairing", "film") || companionFileResult != null) {
            callback(Result.failure(FlutterError("companionPickerBusy", "文件选择暂不可用"))); return
        }
        companionFileLimit = if (kind == "pairing") 4096 else 18432
        companionFileResult = callback
        try { startActivityForResult(Intent(Intent.ACTION_OPEN_DOCUMENT).apply { addCategory(Intent.CATEGORY_OPENABLE); type = "*/*" }, 7214) }
        catch (error: Throwable) { companionFileResult = null; callback(Result.failure(FlutterError("companionPickerFailed", "无法打开文件选择器"))) }
    }
    @Deprecated("Activity callback retained for FlutterActivity document picker")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        if (requestCode != 7214) { super.onActivityResult(requestCode, resultCode, data); return }
        val callback = companionFileResult ?: return
        companionFileResult = null
        if (resultCode != Activity.RESULT_OK) { callback(Result.success(null)); return }
        try {
            val uri = data?.data ?: throw IllegalArgumentException()
            val bytes = contentResolver.openInputStream(uri)?.use { input ->
                val output = java.io.ByteArrayOutputStream(); val buffer = ByteArray(4096)
                while (true) { val count = input.read(buffer, 0, minOf(buffer.size, companionFileLimit + 1 - output.size())); if (count < 0) break; output.write(buffer, 0, count); if (output.size() > companionFileLimit) throw IllegalArgumentException() }
                output.toByteArray()
            } ?: throw IllegalArgumentException()
            callback(Result.success(bytes))
        } catch (error: Throwable) { callback(Result.failure(FlutterError("invalidCompanionFile", "文件读取失败或超过大小限制"))) }
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
        location?.close()
        location = null
        wifiScanController?.close()
        wifiScanController = null
        CameraDeviceHostApi.setUp(messenger, null)
        MediaHostApi.setUp(messenger, null)
        companionFileResult?.invoke(Result.failure(FlutterError("companionPickerCancelled", "文件选择已取消")))
        companionFileResult = null
        deviceApi?.close()
        deviceApi = null
        mediaApi?.close()
        mediaApi = null
        importHistory?.close()
        importHistory = null
        super.cleanUpFlutterEngine(flutterEngine)
    }
}
