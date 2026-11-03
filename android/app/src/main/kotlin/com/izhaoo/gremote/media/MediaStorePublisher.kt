package com.izhaoo.gremote.media

import android.content.ContentValues
import android.content.Context
import android.net.Uri
import android.os.Build
import android.os.Environment
import android.provider.MediaStore
import androidx.exifinterface.media.ExifInterface
import java.io.File

/** Copies policy-filtered EXIF into a rendered JPEG and publishes it to Pictures/gremote. */
class MediaStorePublisher(context: Context) {
    private val resolver = context.contentResolver

    fun publish(
        temp: File,
        source: Uri,
        displayName: String,
        keepGps: Boolean,
        width: Int,
        height: Int,
        outputSrgb: Boolean = false,
    ): Uri {
        if (!temp.isFile) throw MediaException("invalidArgument", "Missing rendered file")
        writeExif(temp, source, keepGps, width, height, outputSrgb)
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            insertPending(temp, displayName)
        } else {
            insertLegacy(temp, displayName)
        }
    }

    fun publishGenerated(temp: File, displayName: String, width: Int, height: Int): Uri {
        require(temp.isFile && width > 0 && height > 0)
        val out = ExifInterface(temp)
        ExifPolicy.filter(emptyMap(), false, width, height).forEach { (tag, value) ->
            out.setAttribute(tag, value)
        }
        out.saveAttributes()
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            insertPending(temp, displayName)
        } else { insertLegacy(temp, displayName) }
    }

    fun importPhoto(temp: File, displayName: String): Uri {
        require(temp.isFile && temp.length() in 1..100_000_000)
        val bounds = android.graphics.BitmapFactory.Options().apply { inJustDecodeBounds = true }
        android.graphics.BitmapFactory.decodeFile(temp.path, bounds)
        require(bounds.outMimeType == "image/jpeg" && bounds.outWidth > 0 && bounds.outHeight > 0) { "请选择 JPEG 照片" }
        val safeName = displayName.substringAfterLast('/').substringAfterLast('\\').take(180)
            .let { if (it.endsWith(".jpg", true) || it.endsWith(".jpeg", true)) it else "$it.jpg" }
        val directory = "${Environment.DIRECTORY_PICTURES}/GRemote/Imported"
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) insertPending(temp, safeName, directory)
            else insertLegacy(temp, safeName, directory)
    }

    private fun writeExif(temp: File, source: Uri, keepGps: Boolean, width: Int, height: Int, outputSrgb: Boolean) {
        val tags = resolver.openInputStream(source)?.use { stream ->
            val exif = ExifInterface(stream)
            ExifPolicy.READ_TAGS.mapNotNull { tag -> exif.getAttribute(tag)?.let { tag to it } }
                .toMap()
        } ?: throw MediaException("openFailed", "Cannot read source EXIF")
        val out = ExifInterface(temp)
        ExifPolicy.filter(tags, keepGps, width, height,outputSrgb).forEach { (tag, value) ->
            out.setAttribute(tag, value)
        }
        out.saveAttributes()
    }

    private fun insertPending(temp: File, displayName: String, directory: String = EXPORT_RELATIVE_PATH): Uri {
        val values = ContentValues().apply {
            put(MediaStore.MediaColumns.DISPLAY_NAME, displayName)
            put(MediaStore.MediaColumns.MIME_TYPE, "image/jpeg")
            put(MediaStore.MediaColumns.RELATIVE_PATH, directory)
            put(MediaStore.MediaColumns.IS_PENDING, 1)
        }
        val uri = resolver.insert(
            MediaStore.Images.Media.getContentUri(MediaStore.VOLUME_EXTERNAL_PRIMARY),
            values,
        ) ?: throw MediaException("publishFailed", "MediaStore refused the new entry")
        try {
            val out = resolver.openOutputStream(uri)
                ?: throw MediaException("publishFailed", "Cannot write the new entry")
            out.use { stream -> temp.inputStream().use { it.copyTo(stream) } }
            resolver.update(
                uri,
                ContentValues().apply { put(MediaStore.MediaColumns.IS_PENDING, 0) },
                null,
                null,
            )
            return uri
        } catch (error: Throwable) {
            resolver.delete(uri, null, null)
            throw error
        }
    }

    @Suppress("DEPRECATION")
    private fun insertLegacy(temp: File, displayName: String, directory: String = EXPORT_RELATIVE_PATH): Uri {
        val dir = File(Environment.getExternalStorageDirectory(), directory)
        if (!dir.isDirectory && !dir.mkdirs()) {
            throw MediaException("publishFailed", "Cannot create $EXPORT_RELATIVE_PATH")
        }
        val target = generateSequence(0) { it + 1 }
            .map { n -> if (n == 0) displayName else displayName.substringBeforeLast('.') + "_$n.jpg" }
            .map { File(dir, it) }
            .first { !it.exists() }
        try {
            temp.copyTo(target)
            val values = ContentValues().apply {
                put(MediaStore.MediaColumns.DATA, target.absolutePath)
                put(MediaStore.MediaColumns.DISPLAY_NAME, target.name)
                put(MediaStore.MediaColumns.MIME_TYPE, "image/jpeg")
            }
            return resolver.insert(MediaStore.Images.Media.EXTERNAL_CONTENT_URI, values)
                ?: throw MediaException("publishFailed", "MediaStore refused the new entry")
        } catch (error: Throwable) {
            target.delete()
            throw error
        }
    }
}
