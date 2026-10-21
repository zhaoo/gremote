package com.izhaoo.gremote.device.http

import kotlinx.coroutines.test.runTest
import okhttp3.OkHttpClient
import okhttp3.Protocol
import okhttp3.Response
import okhttp3.ResponseBody.Companion.toResponseBody
import org.junit.Assert.*
import org.junit.Test

class BoundCompanionTransportTest {
    @Test fun companion_cannot_redirect_off_bound_camera() = runTest {
        var calls = 0
        val client = OkHttpClient.Builder().addInterceptor { chain ->
            calls++
            assertEquals("192.168.0.1", chain.request().url.host)
            assertEquals(18743, chain.request().url.port)
            Response.Builder().request(chain.request()).protocol(Protocol.HTTP_1_1)
                .code(302).message("Moved").header("Location", "http://example.com/")
                .body(byteArrayOf().toResponseBody()).build()
        }.build()
        val transport = BoundCompanionTransport(client, "192.168.0.1") { true }
        try { transport.request("GET", "/m10v/v1/state", emptyMap(), null); fail("redirect accepted") }
        catch (error: CameraTransportException) { assertEquals("invalidCompanionTarget", error.code) }
        assertEquals(1, calls)
    }
    @Test fun only_fixed_paths_headers_body_and_current_binding_are_accepted() = runTest {
        var current = true
        var calls = 0
        val client = OkHttpClient.Builder().addInterceptor { chain ->
            calls++
            assertEquals("unchanged", chain.request().header("X-M10V-KeyId"))
            current = false
            Response.Builder().request(chain.request()).protocol(Protocol.HTTP_1_1)
                .code(200).message("OK").body("{}".toResponseBody()).build()
        }.build()
        val transport = BoundCompanionTransport(client, "192.168.0.1") { current }
        for (path in listOf("http://example.com/m10v/v1/state", "/m10v/v1/../state", "/m10v/v1/state?x=1", "/m10v/v1/state%00")) {
            try { transport.request("GET", path, emptyMap(), null); fail("path accepted") }
            catch (error: CameraTransportException) { assertEquals("invalidCompanionTarget", error.code) }
        }
        try { transport.request("GET", "/m10v/v1/state", mapOf("Host" to "other"), null); fail("Host accepted") }
        catch (error: CameraTransportException) { assertEquals("invalidCompanionTarget", error.code) }
        try { transport.request("GET", "/m10v/v1/state", mapOf("X-M10V-KeyId" to "unchanged"), null); fail("stale binding accepted") }
        catch (error: CameraTransportException) { assertEquals("companionSessionChanged", error.code) }
        assertEquals(1, calls)
    }
}
