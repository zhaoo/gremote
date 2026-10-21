package com.izhaoo.gremote.device

import java.io.InputStream
import kotlinx.coroutines.*

/** Owned by one engine. Provider I/O is a sibling worker, never the UI waiter. */
class CompanionFileReader(
    private val scope: CoroutineScope,
    private val io: CoroutineDispatcher = Dispatchers.IO,
) {
    private var generation = 0
    private var worker: Job? = null
    private var waiter: Job? = null
    private var cancelRead: (() -> Unit)? = null
    fun read(limit: Int, open: () -> InputStream, cancel: () -> Unit,
             completion: (Result<ByteArray>) -> Unit) {
        close()
        val token = generation
        cancelRead = cancel
        val task = scope.async(io) {
            runCatching { open().use { input ->
                val out = java.io.ByteArrayOutputStream()
                val buffer = ByteArray(4096)
                while (true) {
                    ensureActive()
                    val count = input.read(buffer, 0, minOf(buffer.size, limit + 1 - out.size()))
                    if (count < 0) break
                    if (count == 0) throw IllegalArgumentException("Empty provider read")
                    out.write(buffer, 0, count)
                    require(out.size() <= limit)
                }
                require(out.size() > 0)
                out.toByteArray()
            } }
        }
        worker = task
        waiter = scope.launch {
            val result = try { withTimeout(15_000) { task.await() } }
                catch (error: Exception) { Result.failure<ByteArray>(error) }
            if (token == generation && isActive) {
                cancel(); task.cancel()
                cancelRead = null
                completion(result)
            }
        }
    }
    fun close() {
        generation++
        cancelRead?.invoke(); cancelRead = null
        waiter?.cancel(); waiter = null
        worker?.cancel(); worker = null
    }
}
