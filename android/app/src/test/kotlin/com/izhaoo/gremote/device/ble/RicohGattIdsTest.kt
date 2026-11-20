package com.izhaoo.gremote.device.ble

import java.util.UUID
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class RicohGattIdsTest {
    @Test fun recognizesCustomNamedCameraFromItsPairingAdvertisement() {
        val pairing = UUID.fromString("0f291746-0c80-4726-87a7-3c501fd3b4b6")
        assertTrue(RicohGattIds.matchesAdvertisement("Street Camera", setOf(pairing)))
        assertTrue(RicohGattIds.matchesAdvertisement("", setOf(RicohGattIds.CAMERA_INFORMATION_SERVICE)))
        assertTrue(RicohGattIds.matchesAdvertisement("RICOH GR IIIx", emptySet()))
        assertFalse(RicohGattIds.matchesAdvertisement("Street Camera", setOf(UUID.randomUUID())))
    }
}
