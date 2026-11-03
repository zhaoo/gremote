package com.izhaoo.gremote

import android.view.WindowManager
import android.content.Intent
import android.app.Activity
import android.os.CancellationSignal
import kotlinx.coroutines.*
import com.izhaoo.gremote.device.CompanionFileReader
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
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private var companionFileResult: ((Result<ByteArray?>) -> Unit)? = null
    private var companionFileLimit = 0
    private var companionReadScope: CoroutineScope? = null
    private var companionFileReader: CompanionFileReader? = null
    private var location: ForegroundLocation? = null
    private var wifiScanController: WifiScanController? = null
    private var deviceApi: GRemoteDeviceHostApi? = null
    private var mediaApi: GRemoteMediaHostApi? = null
    private var importHistory: CameraImportHistory? = null
    private var appInfoChannel: MethodChannel? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        val messenger = flutterEngine.dartExecutor.binaryMessenger
        appInfoChannel = MethodChannel(messenger, "gremote/app_info").also { channel ->
            channel.setMethodCallHandler { call, result ->
                if (call.method != "read") {
                    result.notImplemented()
                } else {
                    try {
                        @Suppress("DEPRECATION")
                        val info = packageManager.getPackageInfo(packageName, 0)
                        @Suppress("DEPRECATION")
                        val buildNumber = if (android.os.Build.VERSION.SDK_INT >= 28)
                            info.longVersionCode.toString() else info.versionCode.toString()
                        result.success(mapOf(
                            "appName" to applicationInfo.loadLabel(packageManager).toString(),
                            "version" to info.versionName,
                            "buildNumber" to buildNumber,
                        ))
                    } catch (_: Exception) {
                        result.error("appInfoUnavailable", "无法读取应用版本", null)
                    }
                }
            }
        }
        companionReadScope = CoroutineScope(SupervisorJob() + Dispatchers.Main.immediate)
        companionFileReader = CompanionFileReader(companionReadScope!!)
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
        if (resultCode != Activity.RESULT_OK) { companionFileResult = null; callback(Result.success(null)); return }
        val uri = data?.data
        val limit = companionFileLimit
        if (uri == null) { companionFileResult = null; callback(Result.failure(FlutterError("invalidCompanionFile", "未选择文件"))); return }
        val signal = CancellationSignal()
        companionFileReader?.read(limit, {
            contentResolver.openAssetFileDescriptor(uri, "r", signal)?.createInputStream()
                ?: throw IllegalArgumentException()
        }, { signal.cancel() }) { result ->
            if (companionFileResult !== callback) return@read
            companionFileResult = null
            callback(result.fold({ Result.success(it) }, {
                Result.failure(FlutterError("invalidCompanionFile", "文件读取失败、超时或超过大小限制"))
            }))
        }
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
        appInfoChannel?.setMethodCallHandler(null)
        appInfoChannel = null
        location?.close()
        location = null
        wifiScanController?.close()
        wifiScanController = null
        CameraDeviceHostApi.setUp(messenger, null)
        MediaHostApi.setUp(messenger, null)
        companionFileReader?.close(); companionFileReader = null
        companionReadScope?.cancel(); companionReadScope = null
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
