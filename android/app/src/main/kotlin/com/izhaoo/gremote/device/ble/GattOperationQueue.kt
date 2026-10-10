package com.izhaoo.gremote.device.ble

import java.util.UUID
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.TimeoutCancellationException
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import kotlinx.coroutines.withTimeout

class GattOperationException(
    val code: String,
    message: String,
    cause: Throwable? = null,
) : Exception(message, cause)

class GattOperationQueue(private val timeoutMs: Long = 8_000) {
    private data class Pending(
        val characteristicId: UUID,
        val result: CompletableDeferred<ByteArray>,
    )

    private val operationMutex = Mutex()
    private val stateLock = Any()
    private var pending: Pending? = null
    private var closed = false

    suspend fun execute(characteristicId: UUID, start: () -> Boolean): ByteArray =
        operationMutex.withLock {
            val current = synchronized(stateLock) {
                if (closed) {
                    throw GattOperationException(
                        code = "bleDisconnected",
                        message = "GATT queue is closed",
                    )
                }
                Pending(characteristicId, CompletableDeferred()).also {
                    pending = it
                }
            }

            try {
                if (!start()) {
                    throw GattOperationException(
                        code = "bleStartFailed",
                        message = "Android rejected GATT operation for $characteristicId",
                    )
                }
                try {
                    withTimeout(timeoutMs) { current.result.await() }
                } catch (error: TimeoutCancellationException) {
                    throw GattOperationException(
                        code = "bleTimeout",
                        message = "GATT operation timed out for $characteristicId",
                        cause = error,
                    )
                }
            } finally {
                synchronized(stateLock) {
                    if (pending === current) {
                        pending = null
                    }
                }
            }
        }

    fun complete(characteristicId: UUID, value: ByteArray): Boolean =
        synchronized(stateLock) {
            val current = pending
            if (current?.characteristicId != characteristicId) {
                return@synchronized false
            }
            current.result.complete(value)
        }

    fun fail(characteristicId: UUID, code: String, message: String): Boolean =
        synchronized(stateLock) {
            val current = pending
            if (current?.characteristicId != characteristicId) {
                return@synchronized false
            }
            current.result.completeExceptionally(GattOperationException(code, message))
        }

    fun cancelAll() {
        synchronized(stateLock) {
            closed = true
            pending?.result?.completeExceptionally(
                GattOperationException(
                    code = "bleDisconnected",
                    message = "GATT connection closed",
                ),
            )
            pending = null
        }
    }
}
