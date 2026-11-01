package com.izhaoo.gremote.media
import org.junit.Assert.*
import org.junit.Test
class AlbumDirectoryTest {
    @Test fun onlyDownloadsAndExplicitImportsBelongToAlbum() {
        assertTrue(isAppAlbumDirectory("Pictures/GRemote/JPEG/"))
        assertTrue(isAppAlbumDirectory("/storage/emulated/0/Pictures/gremote/Imported/"))
        assertFalse(isAppAlbumDirectory("DCIM/Camera/"))
        assertFalse(isAppAlbumDirectory("Pictures/gremote/"))
        assertFalse(isAppAlbumDirectory(null))
    }
}
