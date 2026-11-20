package com.izhaoo.gremote.media

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertThrows
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import org.junit.rules.TemporaryFolder
import java.nio.ByteBuffer
import java.nio.ByteOrder

class M10lClipTest {
    @get:Rule val folder = TemporaryFolder()

    @Test
    fun readsFrameOffsetsAndExactShutterTime() {
        val file = folder.newFile().apply { writeBytes(fixture()) }
        val clip = M10lClip.read(file)
        assertFalse(clip.nv12)
        assertEquals(720, clip.width)
        assertEquals(480, clip.height)
        assertEquals(125_000L, clip.shutterUs)
        assertEquals(400_000L, clip.durationUs)
        assertEquals(listOf(0L, 210_000L), clip.frames.map { it.timestampUs })
        assertEquals(listOf(32L, 44L), clip.frames.map { it.offset })
        assertEquals(listOf(4, 4), clip.frames.map { it.length })
    }

    @Test
    fun readsVersionTwoNv12FrameIndex() {
        val file = folder.newFile().apply { writeBytes(nv12Fixture()) }
        val clip = M10lClip.read(file)
        assertTrue(clip.nv12)
        assertEquals(192, clip.width)
        assertEquals(128, clip.height)
        assertEquals(1_500_000L, clip.shutterUs)
        assertEquals(2_800_000L, clip.durationUs)
        assertEquals(listOf(0L, 1_600_000L), clip.frames.map { it.timestampUs })
        assertEquals(listOf(32L, 36_904L), clip.frames.map { it.offset })
        assertEquals(listOf(36_864, 36_864), clip.frames.map { it.length })
    }

    @Test
    fun rejectsVersionTwoWrongFormatOrFrameSize() {
        val file = folder.newFile()
        val truncated = nv12Fixture().let { it.copyOf(it.size - 1) }
        for (bytes in listOf(nv12Fixture(format = 0), nv12Fixture(frameBytes = 36_862), truncated)) {
            file.writeBytes(bytes)
            assertThrows(IllegalArgumentException::class.java) { M10lClip.read(file) }
        }
    }

    @Test
    fun rejectsInvalidVersionShapeTimingAndTrailingBytes() {
        val file = folder.newFile()
        val bad = listOf(
            fixture().apply { this[4] = 3 },
            fixture().apply { this[8] = 0xCF.toByte() },
            fixture(secondTimestamp = 0),
            fixture(secondTimestamp = 400),
            fixture().apply { this[47] = 0 },
            fixture().copyOf(47),
            fixture() + 0.toByte(),
        )
        for (bytes in bad) {
            file.writeBytes(bytes)
            assertThrows(IllegalArgumentException::class.java) { M10lClip.read(file) }
        }
    }

    private fun fixture(secondTimestamp: Int = 210): ByteArray =
        ByteBuffer.allocate(48).order(ByteOrder.LITTLE_ENDIAN).apply {
            put("M10L".toByteArray()).putShort(1).putShort(2).putShort(720).putShort(480)
            putInt(125).putInt(400).putInt(0)
            for (timestamp in listOf(0, secondTimestamp)) {
                putInt(timestamp).putInt(4)
                put(byteArrayOf(0xff.toByte(), 0xd8.toByte(), 0xff.toByte(), 0xd9.toByte()))
            }
        }.array()

    private fun nv12Fixture(format: Int = 1, frameBytes: Int = 36_864): ByteArray =
        ByteBuffer.allocate(24 + 2 * (8 + frameBytes)).order(ByteOrder.LITTLE_ENDIAN).apply {
            put("M10L".toByteArray()).putShort(2).putShort(2).putShort(192).putShort(128)
            putInt(1500).putInt(2800).putInt(format)
            for (timestamp in listOf(0, 1600)) {
                putInt(timestamp).putInt(frameBytes)
                put(ByteArray(frameBytes) { 0x80.toByte() })
            }
        }.array()
}
