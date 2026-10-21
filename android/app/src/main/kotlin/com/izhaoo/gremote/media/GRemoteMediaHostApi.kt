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

    override fun contentHash(id: Long, callback: (Result<String>) -> Unit) = launchIo(callback) {
        val digest = java.security.MessageDigest.getInstance("SHA-256")
        val stream = activity.contentResolver.openInputStream(reader.uriOf(id))
            ?: throw MediaException("openFailed", "原片不可用")
        stream.use { input ->
            val buffer = ByteArray(65536)
            while (true) { val count = input.read(buffer); if (count < 0) break; digest.update(buffer, 0, count) }
        }
        digest.digest().joinToString("") { "%02x".format(it.toInt() and 0xff) }
    }

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

    override fun publishGenerated(tempPath: String, displayName: String, width: Long, height: Long,
        callback: (Result<String>) -> Unit) = launchIo(callback) {
        publisher.publishGenerated(File(tempPath), displayName, width.toInt(), height.toInt()).toString()
    }

    override fun shareRecipe(card: ByteArray) {
        require(card.isNotEmpty() && card.size <= 16384)
        val dir = File(activity.cacheDir, "recipe-share").apply { mkdirs() }
        // Cards contain no private metadata. Keep them available to the receiving app.
        dir.listFiles()?.filter { it.lastModified() < System.currentTimeMillis()-86400000L }?.forEach { it.delete() }
        val file = File(dir, "recipe-${java.util.UUID.randomUUID()}.json").apply { writeBytes(card) }
        val uri = androidx.core.content.FileProvider.getUriForFile(activity, activity.packageName+".recipe-files", file)
        val send = Intent(Intent.ACTION_SEND).apply {
            type = "application/json"
            putExtra(Intent.EXTRA_STREAM, uri)
            clipData = android.content.ClipData.newRawUri("胶卷配方卡", uri)
            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
        }
        activity.startActivity(Intent.createChooser(send, "分享配方卡"))
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
