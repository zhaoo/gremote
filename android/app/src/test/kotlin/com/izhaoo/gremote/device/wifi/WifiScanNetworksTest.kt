package com.izhaoo.gremote.device.wifi

import org.junit.Assert.assertEquals
import org.junit.Test

class WifiScanNetworksTest {
    @Test
    fun cameraNetworksComeFirstThenSignalStrengthAndExactIdentityIsPreserved() {
        val actual = WifiScanNetworks.select(listOf(
            WifiScanNetwork("Home", -20),
            WifiScanNetwork("RICOH_GR_01", -90),
            WifiScanNetwork(" Home ", -40),
            WifiScanNetwork("RICOH_GR_02", -60),
            WifiScanNetwork("Home", -50),
            WifiScanNetwork("home", -30),
        ))
        assertEquals(listOf("RICOH_GR_02", "RICOH_GR_01", "Home", "home", " Home "), actual.map { it.ssid })
        assertEquals(-20, actual.single { it.ssid == "Home" }.rssi)
    }

    @Test
    fun invalidHiddenAndOversizedSsidsAreExcludedUsingUtf8ByteLength() {
        val actual = WifiScanNetworks.select(listOf(
            WifiScanNetwork("", -20),
            WifiScanNetwork("<unknown ssid>", -20),
            WifiScanNetwork("x".repeat(33), -20),
            WifiScanNetwork("相".repeat(11), -20),
            WifiScanNetwork("相".repeat(10), -20),
            WifiScanNetwork("x".repeat(32), -20),
        ))
        assertEquals(setOf("相".repeat(10), "x".repeat(32)), actual.map { it.ssid }.toSet())
    }

    @Test
    fun limitIsAppliedAfterCameraPriorityAndStrongestSignalSelection() {
        val actual = WifiScanNetworks.select(
            (0 until 100).map { WifiScanNetwork("home_$it", -it) } +
                WifiScanNetwork("RICOH_GR", -120),
        )
        assertEquals(64, actual.size)
        assertEquals("RICOH_GR", actual.first().ssid)
        assertEquals("home_62", actual.last().ssid)
    }
}
