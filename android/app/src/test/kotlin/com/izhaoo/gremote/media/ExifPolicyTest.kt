package com.izhaoo.gremote.media

import androidx.exifinterface.media.ExifInterface
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class ExifPolicyTest {
    private val source = mapOf(
        ExifInterface.TAG_MAKE to "RICOH IMAGING COMPANY, LTD.",
        ExifInterface.TAG_MODEL to "RICOH GR III",
        ExifInterface.TAG_DATETIME_ORIGINAL to "2026:10:10 08:30:00",
        ExifInterface.TAG_EXPOSURE_TIME to "0.004",
        ExifInterface.TAG_F_NUMBER to "2.8",
        ExifInterface.TAG_PHOTOGRAPHIC_SENSITIVITY to "200",
        ExifInterface.TAG_FOCAL_LENGTH to "183/10",
        ExifInterface.TAG_FOCAL_LENGTH_IN_35MM_FILM to "28",
        ExifInterface.TAG_WHITE_BALANCE to "0",
        ExifInterface.TAG_COLOR_SPACE to "1",
        ExifInterface.TAG_ORIENTATION to "6",
        ExifInterface.TAG_PIXEL_X_DIMENSION to "6000",
        ExifInterface.TAG_PIXEL_Y_DIMENSION to "4000",
        ExifInterface.TAG_SOFTWARE to "GR III Ver 2.00",
        ExifInterface.TAG_BODY_SERIAL_NUMBER to "00012345",
        ExifInterface.TAG_LENS_SERIAL_NUMBER to "L-9",
        ExifInterface.TAG_CAMERA_OWNER_NAME to "zhaoo",
        ExifInterface.TAG_IMAGE_UNIQUE_ID to "abc",
        ExifInterface.TAG_MAKER_NOTE to "binary",
        ExifInterface.TAG_USER_COMMENT to "secret",
        ExifInterface.TAG_GPS_LATITUDE to "30/1,15/1,0/1",
        ExifInterface.TAG_GPS_LATITUDE_REF to "N",
        ExifInterface.TAG_GPS_LONGITUDE to "120/1,10/1,0/1",
        ExifInterface.TAG_GPS_LONGITUDE_REF to "E",
        ExifInterface.TAG_GPS_DATESTAMP to "2026:10:10",
    )

    @Test
    fun keepsShootingFactsAndDropsPrivateTags() {
        val out = ExifPolicy.filter(source, keepGps = false, width = 2560, height = 3413)
        assertEquals("RICOH GR III", out[ExifInterface.TAG_MODEL])
        assertEquals("2.8", out[ExifInterface.TAG_F_NUMBER])
        assertEquals("28", out[ExifInterface.TAG_FOCAL_LENGTH_IN_35MM_FILM])
        assertEquals("2026:10:10 08:30:00", out[ExifInterface.TAG_DATETIME_ORIGINAL])
        listOf(
            ExifInterface.TAG_BODY_SERIAL_NUMBER,
            ExifInterface.TAG_LENS_SERIAL_NUMBER,
            ExifInterface.TAG_CAMERA_OWNER_NAME,
            ExifInterface.TAG_IMAGE_UNIQUE_ID,
            ExifInterface.TAG_MAKER_NOTE,
            ExifInterface.TAG_USER_COMMENT,
        ).forEach { assertFalse(it, out.containsKey(it)) }
    }

    @Test
    fun stripsAllGpsByDefault() {
        val out = ExifPolicy.filter(source, keepGps = false, width = 1, height = 1)
        assertTrue(out.keys.none { it.startsWith("GPS") })
    }

    @Test
    fun keepsGpsWhenAsked() {
        val out = ExifPolicy.filter(source, keepGps = true, width = 1, height = 1)
        assertEquals("30/1,15/1,0/1", out[ExifInterface.TAG_GPS_LATITUDE])
        assertEquals("E", out[ExifInterface.TAG_GPS_LONGITUDE_REF])
        assertEquals("2026:10:10", out[ExifInterface.TAG_GPS_DATESTAMP])
    }

    @Test
    fun overridesOrientationSizeAndSoftware() {
        val out = ExifPolicy.filter(source, keepGps = false, width = 2560, height = 3413)
        assertEquals("1", out[ExifInterface.TAG_ORIENTATION])
        assertEquals("2560", out[ExifInterface.TAG_PIXEL_X_DIMENSION])
        assertEquals("3413", out[ExifInterface.TAG_PIXEL_Y_DIMENSION])
        assertEquals("GRemote", out[ExifInterface.TAG_SOFTWARE])
    }

    @Test
    fun readTagsCoverEverythingThePolicyCanKeep() {
        assertTrue(ExifPolicy.READ_TAGS.containsAll(ExifPolicy.KEPT_TAGS))
        assertTrue(ExifPolicy.READ_TAGS.containsAll(ExifPolicy.GPS_TAGS))
    }
}
