package com.izhaoo.gremote.media

import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class LocalPhotoPolicyTest {
    @Test fun cameraOriginalsRemainVisibleAlongsideExportFolder() {
        assertTrue(includeLocalPhotoDirectory("Pictures/GRemote/JPEG/"))
        assertTrue(includeLocalPhotoDirectory("Pictures/gremote/JPEG/"))
        assertTrue(includeLocalPhotoDirectory("/storage/emulated/0/Pictures/GRemote/JPEG/"))
        assertTrue(includeLocalPhotoDirectory("DCIM/100RICOH/"))
        assertTrue(includeLocalPhotoDirectory(null))
    }

    @Test fun renderedCopiesStillStayOutOfSourceLibrary() {
        assertFalse(includeLocalPhotoDirectory("Pictures/gremote/"))
        assertFalse(includeLocalPhotoDirectory("Pictures/GRemote/"))
        assertFalse(includeLocalPhotoDirectory("/storage/emulated/0/Pictures/gremote/"))
        assertFalse(includeLocalPhotoDirectory("Pictures/m10v/"))
        assertFalse(includeLocalPhotoDirectory("Pictures/m10v/exports/"))
    }
}
