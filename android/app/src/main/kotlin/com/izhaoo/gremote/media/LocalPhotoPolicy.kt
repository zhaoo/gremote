package com.izhaoo.gremote.media

import java.util.Locale

/** Exported renders live directly in Pictures/gremote; camera originals use subfolders. */
internal fun includeLocalPhotoDirectory(directory: String?): Boolean {
    if (directory == null) return true
    val path = "/" + directory.trim('/').lowercase(Locale.ROOT)
    return !path.endsWith("/pictures/gremote") &&
        !path.endsWith("/pictures/m10v") &&
        !path.contains("/pictures/m10v/")
}
