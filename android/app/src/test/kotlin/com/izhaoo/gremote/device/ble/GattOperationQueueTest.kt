package com.izhaoo.gremote.device.ble

import java.util.UUID
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.async
import kotlinx.coroutines.test.advanceTimeBy
import kotlinx.coroutines.test.runCurrent
import kotlinx.coroutines.test.runTest
import org.junit.Assert.assertArrayEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

@OptIn(ExperimentalCoroutinesApi::class)
class GattOperationQueueTest {
    private val firstId = UUID.fromString("35fe6272-6aa5-44d9-88e1-f09427f51a71")
    private val secondId = UUID.fromString("b4eb8905-7411-40a6-a367-2834c2157ea7")

    @Test
    fun serializesOperationsAndMatchesCallbacksByUuid() = runTest {
        val queue = GattOperationQueue(timeoutMs = 1_000)
        var firstStarted = false
        var secondStarted = false

        val first = async {
            runCatching {
                queue.execute(firstId) {
                    firstStarted = true
                    true
                }
            }
        }
        val second = async {
            runCatching {
                queue.execute(secondId) {
                    secondStarted = true
                    true
                }
            }
        }
        runCurrent()

        assertTrue(firstStarted)
        assertFalse(secondStarted)
        assertFalse(queue.complete(secondId, byteArrayOf(9)))
        assertTrue(queue.complete(firstId, byteArrayOf(1)))
        runCurrent()

        assertArrayEquals(byteArrayOf(1), first.await().getOrThrow())
        assertTrue(secondStarted)
        assertTrue(queue.complete(secondId, byteArrayOf(2)))
        assertArrayEquals(byteArrayOf(2), second.await().getOrThrow())
    }

    @Test
    fun mapsTimeoutToStableError() = runTest {
        val queue = GattOperationQueue(timeoutMs = 100)
        val operation = async { runCatching { queue.execute(firstId) { true } } }
        runCurrent()
        advanceTimeBy(101)
        runCurrent()

        val error = operation.await().exceptionOrNull() as GattOperationException
        assertEquals("bleTimeout", error.code)
    }

    @Test
    fun disconnectCancelsPendingAndFutureWork() = runTest {
        val queue = GattOperationQueue(timeoutMs = 1_000)
        val operation = async { runCatching { queue.execute(firstId) { true } } }
        runCurrent()

        queue.cancelAll()
        val pendingError =
            operation.await().exceptionOrNull() as GattOperationException
        val futureError = runCatching {
            queue.execute(secondId) { true }
        }.exceptionOrNull() as GattOperationException
        assertEquals("bleDisconnected", pendingError.code)
        assertEquals("bleDisconnected", futureError.code)
    }
}
