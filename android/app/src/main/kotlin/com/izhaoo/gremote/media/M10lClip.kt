package com.izhaoo.gremote.media

import java.io.File
import java.io.RandomAccessFile

internal data class M10lFrame(val timestampUs: Long, val offset: Long, val length: Int)

/** Validates the complete bounded index before passing frames to Android. */
internal data class M10lClip(
    val width: Int,
    val height: Int,
    val shutterUs: Long,
    val durationUs: Long,
    val frames: List<M10lFrame>,
    val nv12: Boolean = false,
) {
    companion object {
        private const val MAX_FRAME_BYTES = 131_072
        internal const val MAX_BYTES = 24 + 48 * (8 + MAX_FRAME_BYTES)

        fun read(file: File): M10lClip = RandomAccessFile(file, "r").use { input ->
            val size = input.length()
            require(size in 24..MAX_BYTES.toLong() && input.readInt() == 0x4d31304c) { "M10L 短片头无效" }
            val version = input.u16()
            require(version in 1..2) { "M10L 短片版本不受支持" }
            val nv12 = version == 2
            val count = input.u16()
            val width = input.u16()
            val height = input.u16()
            require(count in 2..48 && width in 16..720 && height in 16..480 &&
                width % 2 == 0 && height % 2 == 0) { "M10L 尺寸或帧数无效" }
            val shutter = input.i32()
            val duration = input.i32()
            require(duration in 1..10_000 && shutter in 0..duration) { "M10L 时长无效" }
            require(input.i32() == if (nv12) 1 else 0) { "M10L 帧格式无效" }
            val rawLength = width * height * 3 / 2
            var previous = -1
            val frames = List(count) { _ ->
                require(size - input.filePointer >= 8) { "M10L 帧索引被截断" }
                val timestamp = input.i32()
                val length = input.i32()
                val offset = input.filePointer
                require(timestamp > previous && timestamp < duration) {
                    "M10L 帧时间无效"
                }
                require(length in 4..MAX_FRAME_BYTES && size - offset >= length) { "M10L 帧长度无效" }
                if (nv12) {
                    require(length == rawLength) { "M10L NV12 帧尺寸无效" }
                    input.seek(offset + length)
                } else {
                    require(input.readUnsignedShort() == 0xffd8) { "M10L 缺少 JPEG 帧头" }
                    input.seek(offset + length - 2)
                    require(input.readUnsignedShort() == 0xffd9) { "M10L 缺少 JPEG 帧尾" }
                }
                previous = timestamp
                M10lFrame(timestamp * 1_000L, offset, length)
            }
            require(input.filePointer == size) { "M10L 帧之后有多余的数据" }
            M10lClip(width, height, shutter * 1_000L, duration * 1_000L, frames, nv12)
        }

        private fun RandomAccessFile.u16(): Int = java.lang.Short.reverseBytes(readShort()).toInt() and 0xffff
        private fun RandomAccessFile.i32(): Int = Integer.reverseBytes(readInt())
    }
}
