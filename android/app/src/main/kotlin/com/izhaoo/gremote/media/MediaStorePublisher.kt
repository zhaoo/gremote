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
    ): Uri {
        if (!temp.isFile) throw MediaException("invalidArgument", "Missing rendered file")
        writeExif(temp, source, keepGps, width, height)
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            insertPending(temp, displayName)
        } else {
            insertLegacy(temp, displayName)
        }
    }

    private fun writeExif(temp: File, source: Uri, keepGps: Boolean, width: Int, height: Int) {
        val tags = resolver.openInputStream(source)?.use { stream ->
            val exif = ExifInterface(stream)
            ExifPolicy.READ_TAGS.mapNotNull { tag -> exif.getAttribute(tag)?.let { tag to it } }
                .toMap()
        } ?: throw MediaException("openFailed", "Cannot read source EXIF")
        val out = ExifInterface(temp)
        ExifPolicy.filter(tags, keepGps, width, height).forEach { (tag, value) ->
            out.setAttribute(tag, value)
        }
        out.saveAttributes()
    }

    private fun insertPending(temp: File, displayName: String): Uri {
        val values = ContentValues().apply {
            put(MediaStore.MediaColumns.DISPLAY_NAME, displayName)
            put(MediaStore.MediaColumns.MIME_TYPE, "image/jpeg")
            put(MediaStore.MediaColumns.RELATIVE_PATH, EXPORT_RELATIVE_PATH)
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
    private fun insertLegacy(temp: File, displayName: String): Uri {
        val dir = File(Environment.getExternalStorageDirectory(), EXPORT_RELATIVE_PATH)
        if (!dir.isDirectory && !dir.mkdirs()) {
            throw MediaException("publishFailed", "Cannot create $EXPORT_RELATIVE_PATH")
        }
        val target = generateSequence(0) { it + 1 }
            .map { n -> if (n == 0) displayName else displayName.replace(".jpg", "_$n.jpg") }
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
