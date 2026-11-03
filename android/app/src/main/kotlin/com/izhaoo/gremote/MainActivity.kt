package com.izhaoo.gremote

import android.view.WindowManager
import com.izhaoo.gremote.imaging.GpuEditorHost
import android.content.Intent
import android.app.Activity
import android.os.CancellationSignal
import kotlinx.coroutines.*
import com.izhaoo.gremote.device.CompanionFileReader
import com.izhaoo.gremote.device.FilmLibraryExport
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
    private companion object {
        val exportRequestCounter = java.util.concurrent.atomic.AtomicInteger()
    }
    private var filmExportRequestCode: Int? = null
    private var companionFileResult: ((Result<ByteArray?>) -> Unit)? = null
    private var companionFileLimit = 0
    private var companionReadScope: CoroutineScope? = null
    private var companionFileReader: CompanionFileReader? = null
    private var filmLibraryExport: FilmLibraryExport? = null
    private var location: ForegroundLocation? = null
    private var wifiScanController: WifiScanController? = null
    private var deviceApi: GRemoteDeviceHostApi? = null
    private var mediaApi: GRemoteMediaHostApi? = null
    private var importHistory: CameraImportHistory? = null
    private var appInfoChannel: MethodChannel? = null
    private var gpuEditor: GpuEditorHost? = null

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
        filmLibraryExport = FilmLibraryExport(companionReadScope!!, {
            val requestCode = 27200 + (exportRequestCounter.getAndIncrement() and 255)
            filmExportRequestCode = requestCode
            startActivityForResult(Intent(Intent.ACTION_CREATE_DOCUMENT).apply {
                addCategory(Intent.CATEGORY_OPENABLE)
                type = "application/octet-stream"
                putExtra(Intent.EXTRA_TITLE, "FILMS.M10")
                addFlags(Intent.FLAG_GRANT_WRITE_URI_PERMISSION)
            }, requestCode)
        })
        wifiScanController = WifiScanController(this, messenger)
        location = ForegroundLocation(this, messenger)
        deviceApi = GRemoteDeviceHostApi(
            context = applicationContext,
            flutterApi = CameraDeviceFlutterApi(messenger),
            keepScreenOn = ::setKeepScreenOn,
            pickFile = ::pickCompanionFile,
            exportLibrary = { bytes, callback ->
                if (companionFileResult != null || filmLibraryExport == null) {
                    callback(Result.failure(FlutterError("filmLibraryExportBusy", "文件导出暂不可用")))
                } else {
                    filmLibraryExport!!.begin(bytes) { result ->
                        callback(result.fold({ Result.success(it) }, {
                            Result.failure(FlutterError(
                                if (it is IllegalArgumentException) "invalidFilmLibrary" else "filmLibraryExportFailed",
                                it.message ?: "胶卷库导出失败"))
                        }))
                    }
                }
            },
        ).also { CameraDeviceHostApi.setUp(messenger, it) }
        mediaApi = GRemoteMediaHostApi(this).also { MediaHostApi.setUp(messenger, it) }
        importHistory = CameraImportHistory(applicationContext, messenger)
        gpuEditor = GpuEditorHost(messenger, flutterEngine.renderer)
    }

    override fun onResume() {
        super.onResume()
        location?.onResume()
        gpuEditor?.onResume()
    }

    override fun onTrimMemory(level: Int) {
        super.onTrimMemory(level)
        gpuEditor?.onTrimMemory(level)
    }

    override fun onPause() {
        location?.onPause()
        gpuEditor?.onPause()
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
        if (kind !in setOf("pairing", "film") || companionFileResult != null || filmLibraryExport?.isPending == true) {
            callback(Result.failure(FlutterError("companionPickerBusy", "文件选择暂不可用"))); return
        }
        companionFileLimit = if (kind == "pairing") 4096 else 18432
        companionFileResult = callback
        try { startActivityForResult(Intent(Intent.ACTION_OPEN_DOCUMENT).apply { addCategory(Intent.CATEGORY_OPENABLE); type = "*/*" }, 7214) }
        catch (error: Throwable) { companionFileResult = null; callback(Result.failure(FlutterError("companionPickerFailed", "无法打开文件选择器"))) }
    }
    @Deprecated("Activity callback retained for FlutterActivity document picker")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        if (requestCode in 27200..27455) {
            if (requestCode != filmExportRequestCode) return
            filmExportRequestCode = null
            if (resultCode != Activity.RESULT_OK) {
                filmLibraryExport?.finish(null)
            } else {
                val uri = data?.data
                // The only destination is the URI explicitly chosen by the
                // user. ACTION_CREATE_DOCUMENT lets the provider handle names
                // and any overwrite confirmation; no SD path is assumed.
                filmLibraryExport?.finish {
                    requireNotNull(uri) { "未选择导出位置" }
                    contentResolver.openOutputStream(uri, "w")
                        ?: throw IllegalStateException("无法打开导出位置")
                }
            }
            return
        }
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
        gpuEditor?.close()
        gpuEditor = null
        appInfoChannel?.setMethodCallHandler(null)
        appInfoChannel = null
        location?.close()
        location = null
        wifiScanController?.close()
        wifiScanController = null
        CameraDeviceHostApi.setUp(messenger, null)
        MediaHostApi.setUp(messenger, null)
        filmExportRequestCode = null
        filmLibraryExport?.close(); filmLibraryExport = null
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
