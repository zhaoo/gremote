package com.izhaoo.gremote.media

import java.io.ByteArrayOutputStream
import java.io.File
import java.io.OutputStream
import java.io.RandomAccessFile
import java.io.StringReader
import java.nio.ByteBuffer
import java.nio.file.Files
import java.nio.file.StandardOpenOption.CREATE_NEW
import java.nio.file.StandardOpenOption.WRITE
import javax.xml.XMLConstants.XMLNS_ATTRIBUTE_NS_URI
import javax.xml.parsers.DocumentBuilderFactory
import javax.xml.transform.OutputKeys
import javax.xml.transform.TransformerFactory
import javax.xml.transform.dom.DOMSource
import javax.xml.transform.stream.StreamResult
import org.w3c.dom.Element
import org.xml.sax.InputSource
import org.xml.sax.SAXException

/** Packages a standalone JPEG and a compatible MP4 without re-encoding either input. */
internal object MotionPhotoExporter {
    fun write(
        jpeg: File,
        mp4: File,
        output: File,
        presentationTimestampUs: Long? = null,
    ) {
        require(presentationTimestampUs == null || presentationTimestampUs >= 0) { "视频帧时间无效" }
        RandomAccessFile(jpeg, "r").use { image ->
            RandomAccessFile(mp4, "r").use { video ->
                val jpegLength = image.length()
                val videoLength = video.length()
                val header = readJpegHeader(image, jpegLength)
                requireMp4(video, videoLength)
                val xmp = motionXmp(header.xmp, videoLength, presentationTimestampUs)
                val size = XMP_HEADER.size + xmp.size + 2
                require(size <= 0xffff) { "JPEG 的 XMP 数据过大" }

                // Open exclusively so callers can never overwrite an input or existing export.
                val target = Files.newOutputStream(output.toPath(), CREATE_NEW, WRITE)
                try {
                    target.buffered(COPY_BUFFER).use { out ->
                        val buffer = ByteArray(COPY_BUFFER)
                        image.seek(0)
                        copy(image, out, buffer, header.start)
                        out.write(byteArrayOf(0xff.toByte(), 0xe1.toByte(), (size shr 8).toByte(), size.toByte()))
                        out.write(XMP_HEADER)
                        out.write(xmp)
                        image.seek(header.end)
                        copy(image, out, buffer, jpegLength - header.end)
                        video.seek(0)
                        copy(video, out, buffer, videoLength)
                    }
                } catch (error: Throwable) {
                    output.delete()
                    throw error
                }
            }
        }
    }

    private data class JpegHeader(val start: Long, val end: Long, val xmp: ByteArray?)

    private fun readJpegHeader(input: RandomAccessFile, length: Long): JpegHeader {
        require(length >= 6 && input.readUnsignedShort() == 0xffd8) { "请选择 JPEG 照片" }
        input.seek(length - 2)
        require(input.readUnsignedShort() == 0xffd9) { "须使用未附加视频或增益图的 JPEG 照片" }
        input.seek(2)
        var insertAt = 2L
        var xmp: JpegHeader? = null
        // Walk only JPEG headers. Pixel data and the rest of the file are copied in blocks.
        while (input.filePointer < length - 2) {
            val start = input.filePointer
            require(input.readUnsignedByte() == 0xff) { "JPEG 段标记无效" }
            var marker: Int
            do {
                marker = input.readUnsignedByte()
            } while (marker == 0xff)
            require(marker !in 0xd0..0xd9 && marker != 0x00 && marker != 0x01) { "JPEG 段标记无效" }
            val size = input.readUnsignedShort()
            val payloadStart = input.filePointer
            val end = payloadStart + size - 2
            require(size >= 2 && end <= length - 2) { "JPEG 段长度无效" }
            if (marker == 0xda) return xmp ?: JpegHeader(insertAt, insertAt, null)
            if (marker in 0xe0..0xef && start == insertAt) insertAt = end
            if (marker == 0xe1 || marker == 0xe2) {
                val signature = ByteArray(minOf(size - 2, EXTENDED_XMP_HEADER.size))
                input.readFully(signature)
                require(marker != 0xe2 || !signature.startsWith(MPF_HEADER)) { "暂不支持多图或 Ultra HDR JPEG" }
                require(marker != 0xe1 || !signature.startsWith(EXTENDED_XMP_HEADER)) { "暂不支持扩展 XMP 的 JPEG" }
                if (marker == 0xe1 && signature.startsWith(XMP_HEADER)) {
                    require(xmp == null) { "JPEG 中有多份 XMP 数据" }
                    input.seek(payloadStart + XMP_HEADER.size)
                    val packet = ByteArray(size - 2 - XMP_HEADER.size)
                    input.readFully(packet)
                    xmp = JpegHeader(start, end, packet)
                }
            }
            input.seek(end)
        }
        throw IllegalArgumentException("JPEG 缺少图像数据")
    }

    private fun requireMp4(input: RandomAccessFile, length: Long) {
        require(length >= 16) { "请选择 MP4 短片" }
        val size = input.readInt().toLong() and 0xffffffffL
        require(input.readInt() == 0x66747970 && size in 16..length) { "请选择 MP4 短片" }
    }

    private fun motionXmp(existing: ByteArray?, videoLength: Long, timestampUs: Long?): ByteArray {
        val xml = existing?.let { Charsets.UTF_8.newDecoder().decode(ByteBuffer.wrap(it)).toString() }
            ?: EMPTY_XMP
        // Parse as already-decoded UTF-8. Reject DTDs before invoking the Android or JVM parser.
        require(!xml.contains("<!DOCTYPE")) { "JPEG 的 XMP 数据无效" }
        val document = try {
            val builder = DocumentBuilderFactory.newInstance().apply { isNamespaceAware = true }.newDocumentBuilder()
            builder.setEntityResolver { _, _ -> throw SAXException("External entities are unsupported") }
            builder.parse(InputSource(StringReader(xml)))
        } catch (error: SAXException) {
            throw IllegalArgumentException("JPEG 的 XMP 数据无效", error)
        }
        val descriptions = document.getElementsByTagNameNS(RDF, "Description")
        require(document.documentElement.tagName == "x:xmpmeta" && descriptions.length == 1) {
            "暂不支持此 JPEG 的 XMP 结构"
        }
        val description = descriptions.item(0) as Element
        require(description.tagName == "rdf:Description") { "暂不支持此 JPEG 的 XMP 结构" }
        for (name in MOTION_PROPERTIES) {
            description.removeAttributeNS(CAMERA, name)
            val nodes = description.getElementsByTagNameNS(CAMERA, name)
            for (i in nodes.length - 1 downTo 0) nodes.item(i).also { it.parentNode.removeChild(it) }
        }
        val directories = description.getElementsByTagNameNS(CONTAINER, "Directory")
        for (i in directories.length - 1 downTo 0) directories.item(i).also { it.parentNode.removeChild(it) }
        description.setAttributeNS(XMLNS_ATTRIBUTE_NS_URI, "xmlns:Camera", CAMERA)
        description.setAttributeNS(CAMERA, "Camera:MotionPhoto", "1")
        description.setAttributeNS(CAMERA, "Camera:MotionPhotoVersion", "1")
        timestampUs?.let {
            description.setAttributeNS(CAMERA, "Camera:MotionPhotoPresentationTimestampUs", it.toString())
        }

        val directory = document.createElementNS(CONTAINER, "Container:Directory")
        directory.setAttributeNS(XMLNS_ATTRIBUTE_NS_URI, "xmlns:Container", CONTAINER)
        directory.setAttributeNS(XMLNS_ATTRIBUTE_NS_URI, "xmlns:Item", ITEM)
        description.appendChild(directory)
        val sequence = document.createElementNS(RDF, "rdf:Seq")
        directory.appendChild(sequence)
        fun addItem(mime: String, semantic: String, length: Long?) {
            val listItem = document.createElementNS(RDF, "rdf:li")
            listItem.setAttributeNS(RDF, "rdf:parseType", "Resource")
            sequence.appendChild(listItem)
            val item = document.createElementNS(CONTAINER, "Container:Item")
            item.setAttributeNS(ITEM, "Item:Mime", mime)
            item.setAttributeNS(ITEM, "Item:Semantic", semantic)
            length?.let { item.setAttributeNS(ITEM, "Item:Length", it.toString()) }
            listItem.appendChild(item)
        }
        addItem("image/jpeg", "Primary", null)
        addItem("video/mp4", "MotionPhoto", videoLength)
        return ByteArrayOutputStream().use { bytes ->
            val transformer = TransformerFactory.newInstance().newTransformer()
            transformer.setOutputProperty(OutputKeys.OMIT_XML_DECLARATION, "yes")
            transformer.transform(DOMSource(document), StreamResult(bytes))
            bytes.toByteArray()
        }
    }

    private fun ByteArray.startsWith(prefix: ByteArray): Boolean =
        size >= prefix.size && prefix.indices.all { this[it] == prefix[it] }

    private fun copy(input: RandomAccessFile, output: OutputStream, buffer: ByteArray, size: Long) {
        var remaining = size
        while (remaining > 0) {
            val count = minOf(buffer.size.toLong(), remaining).toInt()
            input.readFully(buffer, 0, count)
            output.write(buffer, 0, count)
            remaining -= count
        }
    }

    private const val COPY_BUFFER = 64 * 1024
    private val XMP_HEADER = "http://ns.adobe.com/xap/1.0/\u0000".toByteArray()
    private val EXTENDED_XMP_HEADER = "http://ns.adobe.com/xmp/extension/\u0000".toByteArray()
    private val MPF_HEADER = "MPF\u0000".toByteArray()
    private const val RDF = "http://www.w3.org/1999/02/22-rdf-syntax-ns#"
    private const val CAMERA = "http://ns.google.com/photos/1.0/camera/"
    private const val CONTAINER = "http://ns.google.com/photos/1.0/container/"
    private const val ITEM = "http://ns.google.com/photos/1.0/container/item/"
    private val MOTION_PROPERTIES = listOf(
        "MotionPhoto", "MotionPhotoVersion", "MotionPhotoPresentationTimestampUs",
        "MicroVideo", "MicroVideoVersion", "MicroVideoOffset", "MicroVideoPresentationTimestampUs",
    )
    private const val EMPTY_XMP = """<x:xmpmeta xmlns:x="adobe:ns:meta/">
        <rdf:RDF xmlns:rdf="http://www.w3.org/1999/02/22-rdf-syntax-ns#">
            <rdf:Description rdf:about=""/>
        </rdf:RDF>
    </x:xmpmeta>"""
}
