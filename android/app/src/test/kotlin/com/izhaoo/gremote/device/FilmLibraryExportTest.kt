package com.izhaoo.gremote.device

import java.io.ByteArrayOutputStream
import java.nio.ByteBuffer
import java.nio.ByteOrder
import java.util.zip.CRC32
import kotlinx.coroutines.test.*
import kotlinx.coroutines.ExperimentalCoroutinesApi
import org.junit.Assert.*
import org.junit.Test

@OptIn(ExperimentalCoroutinesApi::class)
class FilmLibraryExportTest {
    private fun library(): ByteArray {
        val bytes = ByteArray(4096 + 12288)
        "M10VSD1\u0000".toByteArray(Charsets.US_ASCII).copyInto(bytes)
        val header = ByteBuffer.wrap(bytes).order(ByteOrder.LITTLE_ENDIAN)
        header.putInt(8, 1); header.putInt(12, bytes.size)
        header.putInt(16, 1); header.putInt(20, 12288)
        header.putInt(24, 239); header.putInt(28, 1)
        header.putInt(4092, CRC32().apply { update(bytes, 0, 4092) }.value.toInt())
        return bytes
    }
    @Test fun malformed_library_is_rejected_before_showing_picker() = runTest {
        var launches = 0
        val exporter = FilmLibraryExport(backgroundScope, { launches++ }, StandardTestDispatcher(testScheduler))
        for (bytes in listOf(ByteArray(0), ByteArray(4096 + 256 * 12288 + 1),
            library().apply { this[0] = 0 }, library().apply { this[16] = 2 },
            library().apply { this[4092] = 0 })) {
            var result: Result<Boolean>? = null
            exporter.begin(bytes) { result = it }
            assertTrue(result!!.isFailure)
        }
        assertEquals(0, launches)
    }
    @Test fun cancelled_picker_never_opens_or_writes_a_destination() = runTest {
        var launches = 0
        var result: Result<Boolean>? = null
        val exporter = FilmLibraryExport(backgroundScope, { launches++ }, StandardTestDispatcher(testScheduler))
        exporter.begin(library()) { result = it }
        exporter.finish(null)
        runCurrent()
        assertEquals(1, launches)
        assertEquals(false, result!!.getOrThrow())
    }
    @Test fun confirmed_destination_receives_exact_frozen_bytes_then_success() = runTest {
        val bytes = library(); val expected = bytes.copyOf()
        val output = ByteArrayOutputStream()
        var result: Result<Boolean>? = null
        val exporter = FilmLibraryExport(backgroundScope, {}, StandardTestDispatcher(testScheduler))
        exporter.begin(bytes) { result = it }
        bytes[5000] = 42
        exporter.finish { output }
        assertNull(result)
        runCurrent()
        assertArrayEquals(expected, output.toByteArray())
        assertEquals(true, result!!.getOrThrow())
    }
    @Test fun close_before_write_discards_pending_work_and_late_result() = runTest {
        var opened = false; var delivered = false
        val exporter = FilmLibraryExport(backgroundScope, {}, StandardTestDispatcher(testScheduler))
        exporter.begin(library()) { delivered = true }
        exporter.finish { opened = true; ByteArrayOutputStream() }
        exporter.close(); runCurrent()
        assertFalse(opened)
        assertFalse(delivered)
    }
}
