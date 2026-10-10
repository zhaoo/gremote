package com.izhaoo.gremote.device.ble

import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class GattDiscoveryGateTest {
    @Test fun staleConnectionCannotDiscoverOrCompleteNewAttempt() {
        val gate = GattDiscoveryGate()
        val first = gate.begin()
        val second = gate.begin()

        assertFalse(gate.isCurrent(first))
        assertFalse(gate.shouldDiscover(first))
        assertTrue(gate.isCurrent(second))
        assertTrue(gate.shouldDiscover(second))
        assertFalse(gate.shouldDiscover(second))
    }

    @Test fun mtuFallbackAndCallbackOnlyStartDiscoveryOnce() {
        val gate = GattDiscoveryGate()
        val attempt = gate.begin()

        assertTrue(gate.shouldDiscover(attempt))
        assertFalse(gate.shouldDiscover(attempt))
        gate.invalidate()
        assertFalse(gate.isCurrent(attempt))
    }
}
