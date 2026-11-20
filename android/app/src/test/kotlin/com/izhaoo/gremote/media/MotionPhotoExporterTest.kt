package com.izhaoo.gremote.media

import org.junit.Assert.assertArrayEquals
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertThrows
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import org.junit.rules.TemporaryFolder
import java.io.File
import java.util.Base64
import javax.xml.parsers.DocumentBuilderFactory

class MotionPhotoExporterTest {
    @get:Rule
    val folder = TemporaryFolder()

    @Test
    fun writesOneJpegWithAnExactMp4TailAndPresentationTimestamp() {
        val still = jpeg()
        val clip = clip()
        val output = File(folder.root, "frame_MP.jpg")

        MotionPhotoExporter.write(still, clip, output, presentationTimestampUs = 1_480_000)

        val bytes = output.readBytes()
        val packet = xmp(bytes)
        val description = packet.getElementsByTagName("rdf:Description").item(0).attributes
        assertEquals("1", description.getNamedItem("Camera:MotionPhoto").nodeValue)
        assertEquals("1", description.getNamedItem("Camera:MotionPhotoVersion").nodeValue)
        assertEquals("1480000", description.getNamedItem("Camera:MotionPhotoPresentationTimestampUs").nodeValue)
        val items = packet.getElementsByTagName("Container:Item")
        assertEquals(2, items.length)
        val imageItem = items.item(0).attributes
        assertEquals("Primary", imageItem.getNamedItem("Item:Semantic").nodeValue)
        assertEquals("image/jpeg", imageItem.getNamedItem("Item:Mime").nodeValue)
        val videoItem = items.item(1).attributes
        assertEquals("MotionPhoto", videoItem.getNamedItem("Item:Semantic").nodeValue)
        assertEquals("video/mp4", videoItem.getNamedItem("Item:Mime").nodeValue)
        assertEquals("24", videoItem.getNamedItem("Item:Length").nodeValue)
        val videoStart = bytes.size - 24
        assertArrayEquals(clip.readBytes(), bytes.copyOfRange(videoStart, bytes.size))
        assertArrayEquals(byteArrayOf(0xff.toByte(), 0xd9.toByte()), bytes.copyOfRange(videoStart - 2, videoStart))
        val xmpSegment = xmpSegment(bytes)
        assertArrayEquals(
            still.readBytes(),
            bytes.copyOfRange(0, xmpSegment.first) + bytes.copyOfRange(xmpSegment.last + 1, videoStart),
        )
    }

    @Test
    fun updatesExistingXmpWithoutDiscardingUnrelatedMetadataOrChangingInputs() {
        val packet = """
            <x:xmpmeta xmlns:x="adobe:ns:meta/">
              <rdf:RDF xmlns:rdf="http://www.w3.org/1999/02/22-rdf-syntax-ns#">
                <rdf:Description rdf:about="" xmlns:xmp="http://ns.adobe.com/xap/1.0/"
                    xmlns:GCamera="http://ns.google.com/photos/1.0/camera/"
                    GCamera:MicroVideoOffset="123" xmp:Rating="4"/>
              </rdf:RDF>
            </x:xmpmeta>
        """.trimIndent()
        val still = jpeg(packet)
        val clip = clip()
        val originalJpeg = still.readBytes()
        val originalClip = clip.readBytes()
        val output = File(folder.root, "frame_MP.jpg")

        MotionPhotoExporter.write(still, clip, output)

        val bytes = output.readBytes()
        val description = xmp(bytes).getElementsByTagName("rdf:Description").item(0).attributes
        assertEquals("4", description.getNamedItem("xmp:Rating").nodeValue)
        assertEquals(null, description.getNamedItem("GCamera:MicroVideoOffset"))
        assertEquals(null, description.getNamedItem("Camera:MotionPhotoPresentationTimestampUs"))
        assertEquals(1, bytes.toString(Charsets.ISO_8859_1).split(XMP_HEADER).size - 1)
        assertArrayEquals(originalJpeg, still.readBytes())
        assertArrayEquals(originalClip, clip.readBytes())
    }

    @Test
    fun rejectsAStillWithAnExistingTrailerWithoutLeavingOutput() {
        val still = jpeg().apply { appendBytes(byteArrayOf(1, 2, 3)) }
        val output = File(folder.root, "frame_MP.jpg")

        assertThrows(IllegalArgumentException::class.java) {
            MotionPhotoExporter.write(still, clip(), output)
        }
        assertFalse(output.exists())
    }

    @Test
    fun rejectsAnInvalidClipWithoutLeavingOutput() {
        val clip = folder.newFile("invalid.mp4").apply { writeText("not an MP4") }
        val output = File(folder.root, "frame_MP.jpg")

        assertThrows(IllegalArgumentException::class.java) {
            MotionPhotoExporter.write(jpeg(), clip, output)
        }
        assertFalse(output.exists())
    }

    @Test
    fun keepsAnExistingDestinationWhenTheFileNameCollides() {
        val output = folder.newFile("frame_MP.jpg").apply { writeText("previous export") }

        assertThrows(java.nio.file.FileAlreadyExistsException::class.java) {
            MotionPhotoExporter.write(jpeg(), clip(), output)
        }
        assertEquals("previous export", output.readText())
    }

    private fun jpeg(packet: String? = null): File {
        val jpeg = Base64.getMimeDecoder().decode(JPEG_FIXTURE)
        return folder.newFile("image.jpg").apply {
            if (packet == null) {
                writeBytes(jpeg)
            } else {
                val payload = (XMP_HEADER + packet).toByteArray(Charsets.UTF_8)
                val size = payload.size + 2
                val marker = byteArrayOf(0xff.toByte(), 0xe1.toByte(), (size shr 8).toByte(), size.toByte())
                writeBytes(jpeg.copyOfRange(0, 2) + marker + payload + jpeg.copyOfRange(2, jpeg.size))
            }
        }
    }

    private fun clip(): File = folder.newFile("clip.mp4").apply {
        // A synthetic ISO Base Media header for the byte-packaging test. Android validates video tracks separately.
        writeBytes(byteArrayOf(0, 0, 0, 24) + "ftypisom".toByteArray() +
            byteArrayOf(0, 0, 0, 0) + "isommp41".toByteArray())
    }

    private fun xmp(jpeg: ByteArray): org.w3c.dom.Document {
        val segment = xmpSegment(jpeg)
        val xml = jpeg.copyOfRange(segment.first + 4 + XMP_HEADER.length, segment.last + 1)
        return DocumentBuilderFactory.newInstance().newDocumentBuilder().parse(xml.inputStream())
    }

    private fun xmpSegment(jpeg: ByteArray): IntRange {
        val start = jpeg.toString(Charsets.ISO_8859_1).indexOf(XMP_HEADER)
        assertTrue(start >= 4)
        val segmentLength = ((jpeg[start - 2].toInt() and 0xff) shl 8) or (jpeg[start - 1].toInt() and 0xff)
        return (start - 4) until (start + segmentLength - 2)
    }

    private companion object {
        const val XMP_HEADER = "http://ns.adobe.com/xap/1.0/\u0000"
        // A 2 × 2 grayscale JPEG encoded and decoded with Pillow.
        const val JPEG_FIXTURE = """
            /9j/4AAQSkZJRgABAQAAAQABAAD/2wBDAAgGBgcGBQgHBwcJCQgKDBQNDAsLDBkSEw8UHRof
            Hh0aHBwgJC4nICIsIxwcKDcpLDAxNDQ0Hyc5PTgyPC4zNDL/wAALCAACAAIBAREA/8QAFAAB
            AAAAAAAAAAAAAAAAAAAAB//EABwQAAICAgMAAAAAAAAAAAAAAAECBQYDBAASYf/aAAgBAQAA
            PwBWg6lW3gI13r0SzNq4iSdLGST1HnP/2Q==
        """
    }
}
