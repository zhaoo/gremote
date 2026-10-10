package com.izhaoo.gremote.device.wifi

import java.util.concurrent.CancellationException
import kotlinx.coroutines.test.runTest
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class CameraProbeOrderTest {
    @Test
    fun probesPrimaryThenFallbackAndAcceptsValidJson() = runTest {
        val attempts = mutableListOf<String>()
        val probe = CameraProbe { baseUrl ->
            attempts += baseUrl
            when (baseUrl) {
                "http://192.168.0.1" -> CameraProbeResult.ConnectionFailure
                "http://192.168.1.1" -> CameraProbeResult.ValidJson
                else -> error("unexpected endpoint")
            }
        }

        val result = CameraProbeOrder(probe).findBaseUrl()

        assertEquals("http://192.168.1.1", result)
        assertEquals(
            listOf("http://192.168.0.1", "http://192.168.1.1"),
            attempts,
        )
    }

    @Test
    fun fallsThroughOnNotFound() = runTest {
        val attempts = mutableListOf<String>()
        val probe = CameraProbe { baseUrl ->
            attempts += baseUrl
            if (baseUrl.endsWith("0.1")) {
                CameraProbeResult.NotFound
            } else {
                CameraProbeResult.ValidJson
            }
        }

        assertEquals("http://192.168.1.1", CameraProbeOrder(probe).findBaseUrl())
        assertEquals(2, attempts.size)
    }

    @Test
    fun invalidResponseStopsWithoutTryingFallback() = runTest {
        val attempts = mutableListOf<String>()
        val probe = CameraProbe { baseUrl ->
            attempts += baseUrl
            CameraProbeResult.InvalidResponse
        }

        val error = runCatching { CameraProbeOrder(probe).findBaseUrl() }.exceptionOrNull()

        assertTrue(error is CameraNetworkException)
        assertEquals("cameraProbeInvalid", (error as CameraNetworkException).code)
        assertEquals(listOf("http://192.168.0.1"), attempts)
    }

    @Test
    fun cancellationStopsWithoutTryingFallback() = runTest {
        val attempts = mutableListOf<String>()
        val probe = CameraProbe { baseUrl ->
            attempts += baseUrl
            throw CancellationException("cancelled")
        }

        val error = runCatching { CameraProbeOrder(probe).findBaseUrl() }.exceptionOrNull()

        assertTrue(error is CancellationException)
        assertEquals(listOf("http://192.168.0.1"), attempts)
    }
}
