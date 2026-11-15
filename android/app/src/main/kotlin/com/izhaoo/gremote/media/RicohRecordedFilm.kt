package com.izhaoo.gremote.media

import java.io.InputStream
import java.util.zip.CRC32

/** Reads camera-owned metadata from the bounded prefix of the original file. */
internal object RicohRecordedFilm {
    private const val maxPrefix = 256 * 1024

    data class Record(val code: Int, val capturedAt: String?, val exposureRecipe: String? = null)

    fun read(input: InputStream): Record? {
        val bytes = ByteArray(maxPrefix)
        var length = 0
        while (length < bytes.size) {
            val count = input.read(bytes, length, bytes.size - length)
            if (count <= 0) break
            length += count
        }
        val root = Directory(bytes, 0, length, false)
        if (root.byte(0) != 255 || root.byte(1) != 216) return readTiff(root, false)

        var marker = 2
        while (root.byte(marker++) == 255) {
            while (root.byte(marker) == 255) marker++
            val type = root.byte(marker++)
            if (type == 0xda || type == 0xd9) break
            val size = root.word(marker) ?: break
            if (size < 2 || !root.contains(marker, size)) break
            if (type == 0xe1 && size >= 8 && root.magic(marker + 2, "Exif\u0000\u0000")) {
                return readTiff(Directory(bytes, marker + 8, marker + size, false), true)
            }
            marker += size
        }
        return null
    }

    private fun readTiff(root: Directory, jpeg: Boolean): Record? {
        val tiff = root.byteOrder(0) ?: return null
        if (tiff.word(2) != 42) return null
        val first = tiff.offset(4) ?: return null
        val exif = tiff.data(first, 0x8769, 4, 4)?.let { tiff.offset(it.first) }
        val entry = if (jpeg) {
            exif?.let { tiff.data(it, 0x927c, 7, null) }
        } else {
            tiff.data(first, 0xc634, 1, null)
        } ?: return null
        val note = Directory(root.bytes, root.start + entry.first, root.start + entry.second, false)
        if (!note.magic(0, "RICOH\u0000")) return null
        val maker = note.byteOrder(6) ?: return null
        val tone = maker.data(8, 0x004f, 3, 2) ?: return null
        val code = maker.word(tone.first)?.takeIf {
            it in 0x1001..0x104e || it in 0x1121..0x114e || it in 0x2000 until (0x2000 + 210 * 235)
        } ?: return null
        val date = exif?.let { tiff.data(it, 0x9003, 2, 20) }
        val capturedAt = date?.first?.takeIf { tiff.byte(it + 19) == 0 }
            ?.let { tiff.bytes.decodeToString(tiff.start + it, tiff.start + it + 19) }
            ?.takeIf { it.matches(Regex("[0-9]{4}:[0-9]{2}:[0-9]{2} [0-9]{2}:[0-9]{2}:[0-9]{2}")) }
        val recipe = maker.data(8, 0xc7f1, 7, null)?.let { (start, end) ->
            val size = end - start
            val signature = when (size) {
                80 -> "MCR1"
                176 -> "MCR2"
                else -> return@let null
            }
            val bytes = maker.bytes
            val at = maker.start + start
            val crcAt = at + size - 4
            val expected = (0..3).fold(0L) { n, i ->
                n or ((bytes[crcAt + i].toLong() and 255) shl (8 * i))
            }
            if (maker.magic(start, signature) &&
                CRC32().apply { update(bytes, at, size - 4) }.value == expected) {
                bytes.copyOfRange(at, at + size).joinToString("") { "%02x".format(it.toInt() and 255) }
            } else null
        }
        return Record(code, capturedAt, recipe)
    }

    private class Directory(val bytes: ByteArray, val start: Int, val end: Int, val little: Boolean) {
        fun contains(at: Int, n: Int) = at >= 0 && n >= 0 && at <= end - start - n
        fun byte(at: Int): Int? = if (contains(at, 1)) bytes[start + at].toInt() and 255 else null
        fun magic(at: Int, text: String) = text.indices.all { byte(at + it) == text[it].code }
        fun byteOrder(at: Int): Directory? = when {
            magic(at, "II") -> Directory(bytes, start, end, true)
            magic(at, "MM") -> Directory(bytes, start, end, false)
            else -> null
        }
        fun word(at: Int): Int? {
            val first = byte(at) ?: return null
            val last = byte(at + 1) ?: return null
            return if (little) first or (last shl 8) else (first shl 8) or last
        }
        fun offset(at: Int): Int? {
            val first = word(at) ?: return null
            val last = word(at + 2) ?: return null
            return (if (little) first or (last shl 16) else (first shl 16) or last).takeIf { it >= 0 }
        }
        fun data(ifd: Int, tag: Int, type: Int, fixedBytes: Int?): Pair<Int, Int>? {
            val count = word(ifd) ?: return null
            if (!contains(ifd, 2 + count * 12)) return null
            repeat(count) { index ->
                val entry = ifd + 2 + index * 12
                if (word(entry) != tag) return@repeat
                if (word(entry + 2) != type) return null
                val units = offset(entry + 4)?.takeIf { it > 0 } ?: return null
                val size = when (type) {
                    3 -> if (units == 1) 2 else return null
                    4 -> if (units == 1) 4 else return null
                    else -> units
                }
                if (fixedBytes != null && size != fixedBytes) return null
                val at = if (size <= 4) entry + 8 else offset(entry + 8) ?: return null
                // DNG private data may be larger than the prefix. Its leading
                // IFD must still be fully present to authenticate ImageTone.
                val available = (end - start - at).coerceAtMost(size)
                if (available <= 0 || (available != size && tag != 0xc634)) return null
                return at to at + available
            }
            return null
        }
    }
}
