package com.izhaoo.gremote.device.ble

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class BatteryPayloadTest {
    @Test fun grIiiOneByteBatteryReportsLevelWithoutAcFlag() {
        val battery = BatteryPayload.parse(byteArrayOf(0x64))
        assertEquals(100, battery.level)
        assertFalse(battery.acPowered)
    }

    @Test fun twoByteBatteryPreservesPowerSource() {
        val battery = BatteryPayload.parse(byteArrayOf(75, 1))
        assertEquals(75, battery.level)
        assertTrue(battery.acPowered)
    }

    @Test fun rejectsInvalidLengthAndLevel() {
        for (bytes in listOf(byteArrayOf(), byteArrayOf(101), byteArrayOf(50, 2), byteArrayOf(50, 0, 1))) {
            try {
                BatteryPayload.parse(bytes)
                throw AssertionError("invalid battery payload accepted")
            } catch (error: RicohBleException) {
                assertEquals("invalidPayload", error.code)
            }
        }
    }
}
