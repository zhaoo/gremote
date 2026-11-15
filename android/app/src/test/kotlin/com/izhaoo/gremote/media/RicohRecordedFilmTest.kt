package com.izhaoo.gremote.media

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test
import java.io.ByteArrayInputStream
import java.util.zip.CRC32

class RicohRecordedFilmTest {
    private fun photo(dng: Boolean, code: Int, snapshot: ByteArray? = null): ByteArray {
        val bytes = ByteArray(maxOf(128, 144 + (snapshot?.size ?: 0)))
        val noteSize = if (snapshot == null) 32 else 80 + snapshot.size
        fun word(at: Int, value: Int) {
            bytes[at] = value.toByte()
            bytes[at + 1] = (value shr 8).toByte()
        }
        fun entry(at: Int, tag: Int, type: Int, count: Int, value: Int) {
            word(at, tag)
            word(at + 2, type)
            word(at + 4, count)
            word(at + 8, value)
        }
        "II".toByteArray().copyInto(bytes)
        word(2, 42)
        word(4, 8)
        word(8, if (dng) 2 else 1)
        if (dng) {
            entry(10, 0xc634, 1, noteSize, 64)
            entry(22, 0x8769, 4, 1, 36)
            word(36, 1)
            entry(38, 0x9003, 2, 20, 104)
        } else {
            entry(10, 0x8769, 4, 1, 32)
            word(32, 2)
            entry(34, 0x927c, 7, noteSize, 64)
            entry(46, 0x9003, 2, 20, 104)
        }
        "2026:11:14 22:30:00\u0000".toByteArray().copyInto(bytes, 104)
        "RICOH\u0000II".toByteArray().copyInto(bytes, 64)
        word(72, if (snapshot == null) 1 else 2)
        entry(74, 0x004f, 3, 1, code)
        if (snapshot != null) {
            entry(86, 0xc7f1, 7, snapshot.size, 80)
            snapshot.copyInto(bytes, 144)
        }
        if (dng) return bytes
        val segmentSize = bytes.size + 8
        return byteArrayOf(-1, -40, -1, -31, (segmentSize shr 8).toByte(), segmentSize.toByte()) +
            "Exif\u0000\u0000".toByteArray() + bytes
    }

    @Test fun readsTheSameRecordedIdentityFromJpegAndDng() {
        for (dng in listOf(false, true)) {
            assertEquals(RicohRecordedFilm.Record(0x114b, "2026:11:14 22:30:00"),
                RicohRecordedFilm.read(ByteArrayInputStream(photo(dng, 0x114b))))
        }
    }

    @Test fun stockSlotAndTruncatedMetadataAreNotRecordedIdentities() {
        assertNull(RicohRecordedFilm.read(ByteArrayInputStream(photo(false, 0x10c))))
        assertNull(RicohRecordedFilm.read(ByteArrayInputStream(photo(true, 0x114b).copyOf(76))))
    }

    @Test fun readsCameraRecipeAndRejectsCorruptionInBothFormats() {
        for ((size, magic) in listOf(80 to "MCR1", 176 to "MCR2")) {
            val snapshot = ByteArray(size)
            magic.toByteArray().copyInto(snapshot)
            val crcAt = size - 4
            val crc = CRC32().apply { update(snapshot, 0, crcAt) }.value
            repeat(4) { snapshot[crcAt + it] = (crc shr (it * 8)).toByte() }
            val expected = snapshot.joinToString("") { "%02x".format(it.toInt() and 255) }
            for (dng in listOf(false, true)) {
                assertEquals(expected,
                    RicohRecordedFilm.read(ByteArrayInputStream(photo(dng, 0x114b, snapshot)))?.exposureRecipe)
                val corrupt = snapshot.copyOf().apply { this[32] = 1 }
                val record = RicohRecordedFilm.read(ByteArrayInputStream(photo(dng, 0x114b, corrupt)))
                assertEquals(0x114b, record?.code)
                assertNull(record?.exposureRecipe)
            }
        }
    }
}
