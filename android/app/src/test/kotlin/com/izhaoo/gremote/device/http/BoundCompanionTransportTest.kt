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
    @Test fun extensions_use_only_exact_routes_on_bound_camera() = runTest {
        val requested = mutableListOf<String>()
        val client = OkHttpClient.Builder().addInterceptor { chain ->
            val request = chain.request()
            assertEquals("192.168.0.1", request.url.host)
            assertEquals(18743, request.url.port)
            requested.add(request.method + " " + request.url.encodedPath)
            Response.Builder().request(request).protocol(Protocol.HTTP_1_1)
                .code(200).message("OK").body("{}".toResponseBody()).build()
        }.build()
        val transport = BoundCompanionTransport(client, "192.168.0.1") { true }
        val id = "ab".repeat(16)
        val allowed = listOf(
            "GET" to "/m10v/v1/extensions/capabilities",
            "GET" to "/m10v/v1/extensions/state",
            "POST" to "/m10v/v1/extensions/operations",
            "GET" to "/m10v/v1/extensions/operations/$id",
        )
        for ((method, path) in allowed) transport.request(method, path, emptyMap(), null)
        assertEquals(allowed.map { (method, path) -> "$method $path" }, requested)
        for (path in listOf(
            "/m10v/v1/extensions", "/m10v/v1/extensions/private",
            "/m10v/v1/extensions/state?x=1", "/m10v/v1/extensions/../state",
            "/m10v/v1/extensions/operations/short",
            "/m10v/v1/extensions/operations/$id/extra",
            "http://example.com/m10v/v1/extensions/state",
        )) {
            try { transport.request("GET", path, emptyMap(), null); fail("path accepted: $path") }
            catch (error: CameraTransportException) { assertEquals("invalidCompanionTarget", error.code) }
        }
        assertEquals(4, requested.size)
    }

}
