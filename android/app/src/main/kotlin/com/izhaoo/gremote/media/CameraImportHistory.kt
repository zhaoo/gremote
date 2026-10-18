package com.izhaoo.gremote.media

import android.content.ContentUris
import android.content.Context
import android.os.Build
import android.provider.MediaStore
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import java.util.Locale

internal fun isCameraImportDirectory(directory: String?): Boolean {
    val path = directory?.trim('/')?.lowercase(Locale.ROOT) ?: return false
    return path == "pictures/gremote/jpeg" || path == "pictures/gremote/dng" ||
        path.endsWith("/pictures/gremote/jpeg") || path.endsWith("/pictures/gremote/dng")
}

/** Reads completed camera originals, including downloads made before this feature existed. */
class CameraImportHistory(context: Context, messenger: BinaryMessenger) {
    private val resolver = context.applicationContext.contentResolver
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Main.immediate)
    private val channel = MethodChannel(messenger, "gremote/import_history")

    init {
        channel.setMethodCallHandler { call, result ->
            if (call.method != "query") {
                result.notImplemented()
            } else {
                scope.launch {
                    try {
                        result.success(withContext(Dispatchers.IO) { query() })
                    } catch (error: Exception) {
                        result.error("importHistoryFailed", "读取导入记录失败", null)
                    }
                }
            }
        }
    }

    private fun query(): List<Map<String, Any>> {
        val modern = Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q
        val collection = if (modern) MediaStore.Images.Media.getContentUri(MediaStore.VOLUME_EXTERNAL)
            else MediaStore.Images.Media.EXTERNAL_CONTENT_URI
        @Suppress("DEPRECATION")
        val pathColumn = if (modern) MediaStore.MediaColumns.RELATIVE_PATH else MediaStore.MediaColumns.DATA
        val projection = arrayOf(MediaStore.MediaColumns._ID, MediaStore.MediaColumns.DISPLAY_NAME,
            MediaStore.MediaColumns.MIME_TYPE, MediaStore.MediaColumns.DATE_ADDED, pathColumn)
        // Pending rows are visible to their owner; exclude them until publication succeeds.
        val selection = if (modern) "${MediaStore.MediaColumns.IS_PENDING} = 0" else null
        val cursor = resolver.query(collection, projection, selection, null,
            "${MediaStore.MediaColumns.DATE_ADDED} DESC")
            ?: throw IllegalStateException("MediaStore returned no cursor")
        return cursor.use { c ->
            val id = c.getColumnIndexOrThrow(MediaStore.MediaColumns._ID)
            val name = c.getColumnIndexOrThrow(MediaStore.MediaColumns.DISPLAY_NAME)
            val mime = c.getColumnIndexOrThrow(MediaStore.MediaColumns.MIME_TYPE)
            val date = c.getColumnIndexOrThrow(MediaStore.MediaColumns.DATE_ADDED)
            val path = c.getColumnIndexOrThrow(pathColumn)
            buildList {
                while (c.moveToNext()) {
                    val location = c.getString(path)
                    val directory = if (modern) location else location?.substringBeforeLast('/')
                    if (!isCameraImportDirectory(directory)) continue
                    val fileName = c.getString(name) ?: continue
                    if (!fileName.endsWith(".jpg", true) && !fileName.endsWith(".jpeg", true) &&
                        !fileName.endsWith(".dng", true)) continue
                    add(mapOf("uri" to ContentUris.withAppendedId(collection, c.getLong(id)).toString(),
                        "name" to fileName, "mime" to (c.getString(mime) ?: ""),
                        "dateAdded" to c.getLong(date)))
                }
            }
        }
    }

    fun close() {
        channel.setMethodCallHandler(null)
        scope.cancel()
    }
}
