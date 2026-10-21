package com.izhaoo.gremote.device

import java.io.ByteArrayInputStream
import kotlinx.coroutines.*
import kotlinx.coroutines.test.*
import org.junit.Assert.*
import org.junit.Test

@OptIn(ExperimentalCoroutinesApi::class)
class CompanionFileReaderTest {
    @Test fun delayed_provider_does_not_block_ui_and_close_discards_result() = runTest {
        val dispatcher = StandardTestDispatcher(testScheduler)
        val reader = CompanionFileReader(backgroundScope, dispatcher)
        var opened = false
        var delivered = false
        reader.read(4, { opened = true; ByteArrayInputStream(byteArrayOf(1,2)) }, {}, { delivered = true })
        assertFalse(opened)
        reader.close()
        runCurrent()
        assertFalse(delivered)
    }
    @Test fun blocked_provider_times_out_on_owner_without_late_callback() = runTest {
        val opened = java.util.concurrent.CountDownLatch(1)
        val release = java.util.concurrent.CountDownLatch(1)
        val reader = CompanionFileReader(backgroundScope, Dispatchers.IO)
        var deliveries = 0
        var cancelled = false
        reader.read(4, {
            opened.countDown()
            release.await(3, java.util.concurrent.TimeUnit.SECONDS)
            ByteArrayInputStream(byteArrayOf(1))
        }, { cancelled = true }, { deliveries++; assertTrue(it.isFailure) })
        assertTrue(opened.await(1, java.util.concurrent.TimeUnit.SECONDS))
        runCurrent()
        advanceTimeBy(15_001); runCurrent()
        assertEquals(1, deliveries)
        assertTrue(cancelled)
        reader.close(); release.countDown()
        runCurrent()
        assertEquals(1, deliveries)
    }
    @Test fun request_keeps_its_limit_and_delivers_on_owner_scope() = runTest {
        val reader = CompanionFileReader(backgroundScope, StandardTestDispatcher(testScheduler))
        var result: Result<ByteArray>? = null
        reader.read(1, { ByteArrayInputStream(byteArrayOf(1,2)) }, {}, { result = it })
        runCurrent()
        assertTrue(result!!.isFailure)
        reader.close()
    }
}
