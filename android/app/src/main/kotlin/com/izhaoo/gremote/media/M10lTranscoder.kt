package com.izhaoo.gremote.media

import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.ImageFormat
import android.media.Image
import android.media.MediaCodec
import android.media.MediaCodecInfo
import android.media.MediaFormat
import android.media.MediaMuxer
import android.os.SystemClock
import kotlinx.coroutines.currentCoroutineContext
import kotlinx.coroutines.ensureActive
import java.io.File
import java.io.RandomAccessFile
import java.nio.ByteBuffer

/** Converts bounded camera JPEG frames into an AVC MP4 without changing frame timestamps. */
internal object M10lTranscoder {
    suspend fun encode(source: File, output: File, expectedShutterUs: Long?): Long {
        val clip = M10lClip.read(source)
        require(expectedShutterUs == null || expectedShutterUs == clip.shutterUs) {
            "配对清单中的快门时间与短片不符"
        }
        check(output.createNewFile()) { "短片临时文件已存在" }
        try {
            encodeClip(source, output, clip)
            return clip.shutterUs
        } catch (error: Throwable) {
            output.delete()
            throw error
        }
    }

    private suspend fun encodeClip(source: File, output: File, clip: M10lClip) {
        val format = MediaFormat.createVideoFormat(MediaFormat.MIMETYPE_VIDEO_AVC, clip.width, clip.height)
        format.setInteger(MediaFormat.KEY_COLOR_FORMAT, MediaCodecInfo.CodecCapabilities.COLOR_FormatYUV420Flexible)
        format.setInteger(MediaFormat.KEY_COLOR_STANDARD, MediaFormat.COLOR_STANDARD_BT601_NTSC)
        format.setInteger(MediaFormat.KEY_COLOR_RANGE, MediaFormat.COLOR_RANGE_LIMITED)
        format.setInteger(MediaFormat.KEY_COLOR_TRANSFER, MediaFormat.COLOR_TRANSFER_SDR_VIDEO)
        format.setInteger(MediaFormat.KEY_FRAME_RATE, (clip.frames.size * 1_000_000L / clip.durationUs).toInt().coerceIn(1, 30))
        format.setInteger(MediaFormat.KEY_I_FRAME_INTERVAL, 1)
        format.setInteger(MediaFormat.KEY_BIT_RATE, (clip.width * clip.height * 5).coerceIn(200_000, 2_000_000))
        val codec = MediaCodec.createEncoderByType(MediaFormat.MIMETYPE_VIDEO_AVC)
        try {
            codec.configure(format, null, null, MediaCodec.CONFIGURE_FLAG_ENCODE)
            codec.start()
            val muxer = MediaMuxer(output.path, MediaMuxer.OutputFormat.MUXER_OUTPUT_MPEG_4)
            try {
                RandomAccessFile(source, "r").use { input -> drain(input, clip, codec, muxer) }
                muxer.stop()
            } finally {
                muxer.release()
            }
        } finally {
            codec.release()
        }
    }

    private suspend fun drain(input: RandomAccessFile, clip: M10lClip, codec: MediaCodec, muxer: MediaMuxer) {
        val info = MediaCodec.BufferInfo()
        val payload = ByteArray(clip.frames.maxOf { it.length })
        val framePixels = clip.width * clip.height
        val pixels = if (clip.nv12) null else IntArray(framePixels)
        var next = 0
        var inputDone = false
        var outputDone = false
        var track = -1
        var samples = 0
        val deadline = SystemClock.elapsedRealtime() + 30_000
        while (!outputDone) {
            currentCoroutineContext().ensureActive()
            check(SystemClock.elapsedRealtime() < deadline) { "短片编码超时" }
            if (!inputDone) {
                val index = codec.dequeueInputBuffer(5_000)
                if (index >= 0) {
                    if (next < clip.frames.size) {
                        val frame = clip.frames[next++]
                        input.seek(frame.offset)
                        input.readFully(payload, 0, frame.length)
                        val image = checkNotNull(codec.getInputImage(index)) { "设备的视频编码器无法接收图像帧" }
                        if (pixels == null) {
                            fillNv12(payload, image, clip.width, clip.height)
                        } else {
                            fillImage(payload, frame.length, pixels, image, clip.width, clip.height)
                        }
                        codec.queueInputBuffer(index, 0, framePixels * 3 / 2, frame.timestampUs, 0)
                    } else {
                        codec.queueInputBuffer(index, 0, 0, 0, MediaCodec.BUFFER_FLAG_END_OF_STREAM)
                        inputDone = true
                    }
                }
            }
            val index = codec.dequeueOutputBuffer(info, 5_000)
            if (index == MediaCodec.INFO_OUTPUT_FORMAT_CHANGED) {
                check(track == -1) { "短片输出格式变化" }
                track = muxer.addTrack(codec.outputFormat)
                muxer.start()
            } else if (index >= 0) {
                try {
                    val flags = info.flags
                    if (info.size > 0 && (flags and MediaCodec.BUFFER_FLAG_CODEC_CONFIG) == 0) {
                        check(track >= 0) { "短片缺少视频轨道" }
                        val packet = checkNotNull(codec.getOutputBuffer(index))
                        // Write the terminal duration separately even when a codec tags its last payload EOS.
                        info.flags = flags and MediaCodec.BUFFER_FLAG_END_OF_STREAM.inv()
                        muxer.writeSampleData(track, packet, info)
                        samples++
                    }
                    outputDone = (flags and MediaCodec.BUFFER_FLAG_END_OF_STREAM) != 0
                } finally {
                    codec.releaseOutputBuffer(index, false)
                }
            }
        }
        check(samples == clip.frames.size) { "短片编码未保留所有帧" }
        info.set(0, 0, clip.durationUs, MediaCodec.BUFFER_FLAG_END_OF_STREAM)
        muxer.writeSampleData(track, ByteBuffer.allocate(0), info)
    }

    private fun checkLayout(image: Image, width: Int, height: Int) {
        check(image.format == ImageFormat.YUV_420_888 && image.planes.size == 3 &&
            image.width >= width && image.height >= height) { "设备的视频帧布局不受支持" }
    }

    private fun fillNv12(payload: ByteArray, image: Image, width: Int, height: Int) {
        checkLayout(image, width, height)
        val (luma, blue, red) = image.planes
        val yBuffer = luma.buffer
        val uBuffer = blue.buffer
        val vBuffer = red.buffer
        for (row in 0 until height) {
            for (column in 0 until width) {
                yBuffer.put(row * luma.rowStride + column * luma.pixelStride, payload[row * width + column])
            }
        }
        val chromaOffset = width * height
        for (row in 0 until height / 2) {
            for (column in 0 until width / 2) {
                val source = chromaOffset + row * width + column * 2
                uBuffer.put(row * blue.rowStride + column * blue.pixelStride, payload[source])
                vBuffer.put(row * red.rowStride + column * red.pixelStride, payload[source + 1])
            }
        }
    }

    private fun fillImage(jpeg: ByteArray, length: Int, pixels: IntArray, image: Image, width: Int, height: Int) {
        val bounds = BitmapFactory.Options().apply { inJustDecodeBounds = true }
        BitmapFactory.decodeByteArray(jpeg, 0, length, bounds)
        require(bounds.outWidth == width && bounds.outHeight == height && bounds.outMimeType == "image/jpeg") {
            "M10L JPEG 帧尺寸与短片头不符"
        }
        val bitmap = requireNotNull(BitmapFactory.decodeByteArray(jpeg, 0, length,
            BitmapFactory.Options().apply { inPreferredConfig = Bitmap.Config.ARGB_8888 })) {
            "无法解码 M10L JPEG 帧"
        }
        try {
            bitmap.getPixels(pixels, 0, width, 0, 0, width, height)
        } finally {
            bitmap.recycle()
        }
        checkLayout(image, width, height)
        val yPlane = image.planes[0]
        val uPlane = image.planes[1]
        val vPlane = image.planes[2]
        val yBuffer = yPlane.buffer
        val uBuffer = uPlane.buffer
        val vBuffer = vPlane.buffer
        val yRow = yPlane.rowStride
        val uRow = uPlane.rowStride
        val vRow = vPlane.rowStride
        val yPixel = yPlane.pixelStride
        val uPixel = uPlane.pixelStride
        val vPixel = vPlane.pixelStride
        // Limited-range Rec.601. Average 2×2 RGB before producing each chroma sample.
        for (y in 0 until height step 2) {
            for (x in 0 until width step 2) {
                var red = 0
                var green = 0
                var blue = 0
                for (row in y..y + 1) for (column in x..x + 1) {
                    val argb = pixels[row * width + column]
                    val r = argb shr 16 and 255
                    val g = argb shr 8 and 255
                    val b = argb and 255
                    red += r
                    green += g
                    blue += b
                    val luma = ((66 * r + 129 * g + 25 * b + 128) shr 8) + 16
                    yBuffer.put(row * yRow + column * yPixel, luma.toByte())
                }
                val u = ((-38 * red - 74 * green + 112 * blue + 512) shr 10) + 128
                val v = ((112 * red - 94 * green - 18 * blue + 512) shr 10) + 128
                uBuffer.put((y / 2) * uRow + (x / 2) * uPixel, u.toByte())
                vBuffer.put((y / 2) * vRow + (x / 2) * vPixel, v.toByte())
            }
        }
    }
}
