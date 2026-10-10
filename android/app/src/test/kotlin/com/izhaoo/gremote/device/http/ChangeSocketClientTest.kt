package com.izhaoo.gremote.device.http

import java.util.concurrent.LinkedBlockingQueue
import java.util.concurrent.TimeUnit
import okhttp3.OkHttpClient
import okhttp3.Response
import okhttp3.WebSocket
import okhttp3.WebSocketListener
import okhttp3.mockwebserver.MockResponse
import okhttp3.mockwebserver.MockWebServer
import org.json.JSONObject
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Before
import org.junit.Test

class ChangeSocketClientTest {
    private val server = MockWebServer()
    private val events = LinkedBlockingQueue<Pair<String, String>>()
    private val serverSockets = LinkedBlockingQueue<WebSocket>()
    private val client = ChangeSocketClient(OkHttpClient()) { type, payload ->
        events.put(type to payload)
    }

    @Before
    fun setUp() = server.start()

    @After
    fun tearDown() {
        client.close()
        server.shutdown()
    }

    private fun enqueueSocket() {
        server.enqueue(MockResponse().withWebSocketUpgrade(object : WebSocketListener() {
            override fun onOpen(webSocket: WebSocket, response: Response) {
                serverSockets.put(webSocket)
            }

            override fun onClosing(webSocket: WebSocket, code: Int, reason: String) {
                webSocket.close(1000, null)
            }
        }))
    }

    private fun url() = server.url("/v1/changes").toString().replaceFirst("http://", "ws://")

    private fun next(): Pair<String, String> =
        events.poll(5, TimeUnit.SECONDS) ?: error("no event")

    @Test
    fun forwardsOpenAndMessagesAsJson() {
        enqueueSocket()
        client.open(url())
        assertEquals("changes.open", next().first)

        serverSockets.poll(5, TimeUnit.SECONDS)!!.send("{\"av\":\"4.0\"}")
        val (type, payload) = next()
        assertEquals("changes.message", type)
        assertEquals("{\"av\":\"4.0\"}", JSONObject(payload).getString("text"))
    }

    @Test
    fun reportsServerClose() {
        enqueueSocket()
        client.open(url())
        assertEquals("changes.open", next().first)

        serverSockets.poll(5, TimeUnit.SECONDS)!!.close(1001, "bye")
        val (type, payload) = next()
        assertEquals("changes.closed", type)
        assertEquals(1001, JSONObject(payload).getInt("code"))
    }

    @Test
    fun reportsHandshakeFailureWithStatus() {
        server.enqueue(MockResponse().setResponseCode(404))
        client.open(url())

        val (type, payload) = next()
        assertEquals("changes.failure", type)
        assertEquals(404, JSONObject(payload).getInt("status"))
    }

    @Test
    fun reopenIgnoresTheOldSocket() {
        enqueueSocket()
        client.open(url())
        assertEquals("changes.open", next().first)
        val first = serverSockets.poll(5, TimeUnit.SECONDS)!!

        enqueueSocket()
        client.open(url())
        assertEquals("changes.open", next().first)

        first.send("{\"stale\":true}")
        assertNull(events.poll(500, TimeUnit.MILLISECONDS))
    }
}
