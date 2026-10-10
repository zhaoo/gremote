package com.izhaoo.gremote.media

import android.app.Activity
import android.content.Intent
import android.net.Uri
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import java.io.File
import java.io.IOException

class GRemoteMediaHostApi(private val activity: Activity) : MediaHostApi {
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Main.immediate)
    private val permissions = MediaPermissions(activity)
    private val reader = MediaStoreReader(activity.applicationContext)
    private val publisher = MediaStorePublisher(activity.applicationContext)

    override fun access(): NativeMediaAccess = permissions.access()

    override fun requestAccess(callback: (Result<NativeMediaAccess>) -> Unit) =
        permissions.requestAccess { callback(Result.success(it)) }

    override fun hasLocationAccess(): Boolean = permissions.hasLocationAccess()

    override fun requestLocationAccess(callback: (Result<Boolean>) -> Unit) =
        permissions.requestLocationAccess { callback(Result.success(it)) }

    override fun queryImages(callback: (Result<List<NativeMediaEntry>>) -> Unit) =
        launchIo(callback) { reader.queryImages() }

    override fun readExif(ids: List<Long>, callback: (Result<List<NativeExifSummary>>) -> Unit) {
        val requireOriginal = permissions.hasLocationAccess()
        launchIo(callback) { reader.readExif(ids, requireOriginal) }
    }

    override fun thumbnail(id: Long, edge: Long, callback: (Result<ByteArray?>) -> Unit) =
        launchIo(callback) { reader.thumbnail(id, edge.toInt().coerceIn(32, 1024)) }

    override fun openReadFd(id: Long, callback: (Result<Long>) -> Unit) =
        launchIo(callback) { reader.openReadFd(id) }

    override fun publishExport(
        tempPath: String,
        sourceId: Long,
        displayName: String,
        keepGps: Boolean,
        width: Long,
        height: Long,
        callback: (Result<String>) -> Unit,
    ) {
        val withGps = keepGps && permissions.hasLocationAccess()
        launchIo(callback) {
            val source = if (withGps) reader.originalUriOf(sourceId) else reader.uriOf(sourceId)
            publisher.publish(
                temp = File(tempPath),
                source = source,
                displayName = displayName,
                keepGps = withGps,
                width = width.toInt(),
                height = height.toInt(),
            ).toString()
        }
    }

    override fun share(uri: String) {
        val send = Intent(Intent.ACTION_SEND).apply {
            type = "image/jpeg"
            putExtra(Intent.EXTRA_STREAM, Uri.parse(uri))
            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
        }
        activity.startActivity(Intent.createChooser(send, null))
    }

    fun onRequestPermissionsResult(requestCode: Int): Boolean =
        permissions.onRequestPermissionsResult(requestCode)

    fun close() = scope.cancel()

    private fun <T> launchIo(callback: (Result<T>) -> Unit, block: () -> T) {
        scope.launch {
            callback(
                try {
                    Result.success(withContext(Dispatchers.IO) { block() })
                } catch (error: Throwable) {
                    Result.failure(error.asFlutterError())
                },
            )
        }
    }

    private fun Throwable.asFlutterError(): FlutterError = when (this) {
        is FlutterError -> this
        is MediaException -> FlutterError(code, message)
        is SecurityException -> FlutterError("permissionDenied", message)
        is IOException -> FlutterError(
            if (message.orEmpty().contains("ENOSPC") || message.orEmpty().contains("No space")) {
                "storageFull"
            } else {
                "ioFailure"
            },
            message,
        )
        is IllegalArgumentException -> FlutterError("invalidArgument", message)
        else -> FlutterError("nativeFailure", message ?: javaClass.simpleName)
    }
}
