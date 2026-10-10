package com.izhaoo.gremote.device.ble

/** Keeps callbacks from an old GATT session out of the current connection. */
class GattDiscoveryGate {
    private var generation = 0
    private var discoveryStarted = false

    @Synchronized fun begin(): Int {
        generation++
        discoveryStarted = false
        return generation
    }

    @Synchronized fun invalidate() {
        generation++
        discoveryStarted = false
    }

    @Synchronized fun isCurrent(attempt: Int) = generation == attempt

    @Synchronized fun shouldDiscover(attempt: Int): Boolean {
        if (generation != attempt || discoveryStarted) return false
        discoveryStarted = true
        return true
    }
}
