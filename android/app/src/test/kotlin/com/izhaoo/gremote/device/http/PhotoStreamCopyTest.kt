package com.izhaoo.gremote.device.http
import java.io.ByteArrayInputStream
import java.io.ByteArrayOutputStream
import org.junit.Assert.assertArrayEquals
import org.junit.Assert.assertEquals
import org.junit.Test
class PhotoStreamCopyTest {
    @Test fun preservesPhotoBytesWithBoundedWrites() {
        val bytes = ByteArray(1024 * 1024 + 13) { (it % 251).toByte() }
        var writes = 0
        val output = object : ByteArrayOutputStream() {
            override fun write(b: ByteArray, off: Int, len: Int) {
                writes++
                super.write(b, off, len)
            }
        }
        assertEquals(bytes.size.toLong(), copyPhotoStream(ByteArrayInputStream(bytes), output))
        assertArrayEquals(bytes, output.toByteArray())
        assertEquals(17, writes)
    }
}
