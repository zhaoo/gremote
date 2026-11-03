package com.izhaoo.gremote.device

import java.io.OutputStream
import java.nio.ByteBuffer
import java.nio.ByteOrder
import java.util.zip.CRC32
import kotlinx.coroutines.*

/** One explicit system-picker export. No camera transport or storage paths. */
class FilmLibraryExport(
    private val scope: CoroutineScope,
    private val showPicker: () -> Unit,
    private val io: CoroutineDispatcher = Dispatchers.IO,
) {
    private var pending: Pair<ByteArray, (Result<Boolean>) -> Unit>? = null
    private var worker: Job? = null
    private var generation = 0
    val isPending: Boolean get() = pending != null

    fun begin(bytes: ByteArray, completion: (Result<Boolean>) -> Unit) {
        if (pending != null) {
            completion(Result.failure(IllegalStateException("文件导出正在进行"))); return
        }
        try {
            validate(bytes)
            pending = bytes.copyOf() to completion
            showPicker()
        } catch (error: Exception) {
            pending = null
            completion(Result.failure(error))
        }
    }

    fun finish(open: (() -> OutputStream)?) {
        val (bytes, completion) = pending ?: return
        if (worker != null) return
        if (open == null) {
            pending = null
            completion(Result.success(false)); return
        }
        val token = generation
        worker = scope.launch {
            val result = withContext(io) {
                runCatching {
                    ensureActive()
                    open().use { output ->
                        ensureActive()
                        output.write(bytes)
                        output.flush()
                    }
                    true
                }
            }
            if (token == generation && isActive) {
                pending = null; worker = null
                completion(result)
            }
        }
    }

    fun close() {
        generation++
        worker?.cancel(); worker = null
        pending = null
    }

    companion object {
        fun validate(bytes: ByteArray) {
            require(bytes.size in 4096..(4096 + 256 * 12288)) { "胶卷库大小无效" }
            require(bytes.copyOfRange(0, 8).contentEquals("M10VSD1\u0000".toByteArray(Charsets.US_ASCII))) { "胶卷库标识无效" }
            val header = ByteBuffer.wrap(bytes).order(ByteOrder.LITTLE_ENDIAN)
            val count = header.getInt(16)
            require(header.getInt(8) == 1 && count in 1..256 &&
                header.getInt(12) == bytes.size && header.getInt(20) == 12288 &&
                bytes.size == 4096 + count * 12288 &&
                header.getInt(24) == 239 && header.getInt(28) == 1) { "胶卷库头部无效" }
            val crc = CRC32().apply { update(bytes, 0, 4092) }.value
            require(crc == (header.getInt(4092).toLong() and 0xffffffffL)) { "胶卷库校验失败" }
        }
    }
}
