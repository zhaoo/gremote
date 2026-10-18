package com.izhaoo.gremote.media

import android.content.ContentUris
import android.content.Context
import android.graphics.Bitmap
import android.net.Uri
import android.os.Build
import android.os.Environment
import android.provider.MediaStore
import android.util.Size
import androidx.exifinterface.media.ExifInterface
import java.io.ByteArrayOutputStream

class MediaException(val code: String, message: String) : Exception(message)

/** Folder exported copies are published into, relative to shared storage. */
val EXPORT_RELATIVE_PATH = "${Environment.DIRECTORY_PICTURES}/gremote"

/** Reads JPEG rows, EXIF summaries, thumbnails and descriptors from MediaStore. */
class MediaStoreReader(context: Context) {
    private val resolver = context.contentResolver

    val collection: Uri =
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            MediaStore.Images.Media.getContentUri(MediaStore.VOLUME_EXTERNAL)
        } else {
            MediaStore.Images.Media.EXTERNAL_CONTENT_URI
        }

    fun uriOf(id: Long): Uri = ContentUris.withAppendedId(collection, id)

    /** Uri that keeps EXIF GPS; only valid once ACCESS_MEDIA_LOCATION is granted. */
    fun originalUriOf(id: Long): Uri =
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            MediaStore.setRequireOriginal(uriOf(id))
        } else {
            uriOf(id)
        }

    /** All JPEGs except the copies gremote exported itself. */
    fun queryImages(): List<NativeMediaEntry> {
        val relative = Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q
        val pathColumn = if (relative) MediaStore.MediaColumns.RELATIVE_PATH else {
            @Suppress("DEPRECATION")
            MediaStore.MediaColumns.DATA
        }
        val projection = arrayOf(
            MediaStore.Images.Media._ID,
            MediaStore.Images.Media.DISPLAY_NAME,
            MediaStore.Images.Media.DATE_MODIFIED,
            MediaStore.Images.Media.DATE_TAKEN,
            MediaStore.Images.Media.WIDTH,
            MediaStore.Images.Media.HEIGHT,
            pathColumn,
        )
        val selection = "${MediaStore.Images.Media.MIME_TYPE} = ?"
        val cursor = resolver.query(
            collection,
            projection,
            selection,
            arrayOf("image/jpeg"),
            "${MediaStore.Images.Media.DATE_TAKEN} DESC",
        ) ?: throw MediaException("queryFailed", "MediaStore returned no cursor")
        return cursor.use { c ->
            val id = c.getColumnIndexOrThrow(MediaStore.Images.Media._ID)
            val name = c.getColumnIndexOrThrow(MediaStore.Images.Media.DISPLAY_NAME)
            val modified = c.getColumnIndexOrThrow(MediaStore.Images.Media.DATE_MODIFIED)
            val taken = c.getColumnIndexOrThrow(MediaStore.Images.Media.DATE_TAKEN)
            val width = c.getColumnIndexOrThrow(MediaStore.Images.Media.WIDTH)
            val height = c.getColumnIndexOrThrow(MediaStore.Images.Media.HEIGHT)
            val path = c.getColumnIndexOrThrow(pathColumn)
            buildList {
                while (c.moveToNext()) {
                    val location = c.getString(path)
                    val directory = if (relative) location else location?.substringBeforeLast('/')
                    if (!includeLocalPhotoDirectory(directory)) continue
                    val rowId = c.getLong(id)
                    add(
                        NativeMediaEntry(
                            id = rowId,
                            uri = uriOf(rowId).toString(),
                            displayName = c.getString(name) ?: "$rowId.jpg",
                            dateModified = c.getLong(modified),
                            dateTaken = if (c.isNull(taken)) null else c.getLong(taken),
                            width = c.getLong(width),
                            height = c.getLong(height),
                        ),
                    )
                }
            }
        }
    }

    /** Unreadable files are skipped; the caller records them as scanned without EXIF. */
    fun readExif(ids: List<Long>, requireOriginal: Boolean): List<NativeExifSummary> =
        ids.mapNotNull { id -> runCatching { summary(id, requireOriginal) }.getOrNull() }

    fun thumbnail(id: Long, edge: Int): ByteArray? {
        val bitmap = runCatching {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                resolver.loadThumbnail(uriOf(id), Size(edge, edge), null)
            } else {
                @Suppress("DEPRECATION")
                MediaStore.Images.Thumbnails.getThumbnail(
                    resolver, id, MediaStore.Images.Thumbnails.MINI_KIND, null,
                )
            }
        }.getOrNull() ?: return null
        return ByteArrayOutputStream().use { out ->
            bitmap.compress(Bitmap.CompressFormat.JPEG, 85, out)
            bitmap.recycle()
            out.toByteArray()
        }
    }

    /** Detached read-only descriptor; ownership passes to the caller. */
    fun openReadFd(id: Long): Long {
        val descriptor = resolver.openFileDescriptor(uriOf(id), "r")
            ?: throw MediaException("openFailed", "Cannot open media $id")
        return descriptor.detachFd().toLong()
    }

    private fun summary(id: Long, requireOriginal: Boolean): NativeExifSummary {
        val uri = if (requireOriginal) originalUriOf(id) else uriOf(id)
        val exif = resolver.openInputStream(uri)?.use(::ExifInterface)
            ?: throw MediaException("openFailed", "Cannot open media $id")
        fun positiveInt(tag: String) = exif.getAttributeInt(tag, 0).takeIf { it > 0 }
        fun positiveDouble(tag: String) = exif.getAttributeDouble(tag, 0.0).takeIf { it > 0 }
        return NativeExifSummary(
            id = id,
            width = (positiveInt(ExifInterface.TAG_IMAGE_WIDTH)
                ?: positiveInt(ExifInterface.TAG_PIXEL_X_DIMENSION) ?: 0).toLong(),
            height = (positiveInt(ExifInterface.TAG_IMAGE_LENGTH)
                ?: positiveInt(ExifInterface.TAG_PIXEL_Y_DIMENSION) ?: 0).toLong(),
            orientation = exif.getAttributeInt(ExifInterface.TAG_ORIENTATION, 1)
                .takeIf { it in 1..8 }?.toLong() ?: 1L,
            make = exif.getAttribute(ExifInterface.TAG_MAKE),
            model = exif.getAttribute(ExifInterface.TAG_MODEL),
            fNumber = positiveDouble(ExifInterface.TAG_F_NUMBER),
            exposureTime = positiveDouble(ExifInterface.TAG_EXPOSURE_TIME),
            iso = positiveInt(ExifInterface.TAG_PHOTOGRAPHIC_SENSITIVITY)?.toLong(),
            focal35 = positiveInt(ExifInterface.TAG_FOCAL_LENGTH_IN_35MM_FILM)?.toLong(),
            focal = positiveDouble(ExifInterface.TAG_FOCAL_LENGTH),
            takenAt = exif.getAttribute(ExifInterface.TAG_DATETIME_ORIGINAL)
                ?: exif.getAttribute(ExifInterface.TAG_DATETIME),
            hasGps = exif.latLong != null,
        )
    }
}
