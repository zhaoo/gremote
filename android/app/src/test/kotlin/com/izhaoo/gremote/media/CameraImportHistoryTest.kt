package com.izhaoo.gremote.media

import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class CameraImportHistoryTest {
    @Test fun onlyOriginalImportDirectoriesAreIncluded() {
        assertTrue(isCameraImportDirectory("Pictures/GRemote/JPEG/"))
        assertTrue(isCameraImportDirectory("Pictures/gremote/DNG/"))
        assertTrue(isCameraImportDirectory("/storage/emulated/0/Pictures/GRemote/JPEG/"))
        assertFalse(isCameraImportDirectory("Pictures/gremote/"))
        assertFalse(isCameraImportDirectory("Pictures/GRemote/JPEG/subfolder/"))
        assertFalse(isCameraImportDirectory("DCIM/100RICOH/"))
        assertFalse(isCameraImportDirectory(null))
    }
}
