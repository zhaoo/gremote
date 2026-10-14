package com.izhaoo.gremote.device.wifi

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class NetworkRequestLifecycleTest {
    @Test
    fun disconnectCompletesThePendingRequestWithoutWaitingForTimeout() {
        val lifecycle = NetworkRequestLifecycle<String>()
        val request = lifecycle.begin()

        assertTrue(lifecycle.end(request))
        assertTrue(request.result.isCancelled)
    }

    @Test
    fun availableAfterDisconnectCannotPublishOrCompleteTheOldRequest() {
        val lifecycle = NetworkRequestLifecycle<String>()
        val request = lifecycle.begin()
        lifecycle.end(request)
        var published = 0

        assertFalse(lifecycle.available(request, "camera-network") { published++ })
        assertEquals(0, published)
        assertTrue(request.result.isCancelled)
    }

    @Test
    fun unavailableFromPreviousRequestCannotRejectTheCurrentRequest() {
        val lifecycle = NetworkRequestLifecycle<String>()
        val old = lifecycle.begin()
        lifecycle.end(old)
        val current = lifecycle.begin()

        assertFalse(lifecycle.unavailable(old, IllegalStateException("rejected")))
        assertFalse(current.result.isCompleted)
        assertTrue(lifecycle.available(current, "camera-network") {})
    }

    @Test
    fun staleLostCallbackCannotLoseTheNewConnectionEvenIfNetworkIsTheSame() {
        val lifecycle = NetworkRequestLifecycle<String>()
        val old = lifecycle.begin()
        lifecycle.available(old, "camera-network") {}
        lifecycle.end(old)
        val current = lifecycle.begin()
        lifecycle.available(current, "camera-network") {}
        var lostEvents = 0

        assertFalse(lifecycle.lost(old, "camera-network") { lostEvents++ })
        assertTrue(lifecycle.lost(current, "camera-network") { lostEvents++ })
        assertEquals(1, lostEvents)
    }

    @Test
    fun cleanupOfOldRequestLeavesNewRequestActive() {
        val lifecycle = NetworkRequestLifecycle<String>()
        val old = lifecycle.begin()
        lifecycle.end(old)
        val current = lifecycle.begin()

        assertFalse(lifecycle.end(old))
        assertTrue(lifecycle.available(current, "camera-network") {})
        assertTrue(current.result.isCompleted)
    }
}
