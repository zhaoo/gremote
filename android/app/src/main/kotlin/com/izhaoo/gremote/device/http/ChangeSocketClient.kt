package com.izhaoo.gremote.device.http

import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.Response
import okhttp3.WebSocket
import okhttp3.WebSocketListener
import org.json.JSONObject

/**
 * Single `/v1/changes` WebSocket (firmware-derived / hardware-unverified).
 *
 * Only the current socket may emit events, so a reopen never leaks events
 * from the previous connection.
 */
class ChangeSocketClient(
    private val client: OkHttpClient,
    private val emitEvent: (String, String) -> Unit,
) {
    private val lock = Any()
    private var current: WebSocket? = null

    fun open(url: String) {
        close()
        val request = Request.Builder().url(url).build()
        synchronized(lock) {
            current = client.newWebSocket(request, Listener())
        }
    }

    fun close() {
        val socket = synchronized(lock) { current.also { current = null } }
        socket?.close(1000, null)
    }

    private fun isCurrent(socket: WebSocket) = synchronized(lock) { current === socket }

    private fun clear(socket: WebSocket) = synchronized(lock) {
        if (current === socket) current = null
    }

    private inner class Listener : WebSocketListener() {
        override fun onOpen(webSocket: WebSocket, response: Response) {
            if (isCurrent(webSocket)) emitEvent("changes.open", "{}")
        }

        override fun onMessage(webSocket: WebSocket, text: String) {
            if (isCurrent(webSocket)) {
                emitEvent("changes.message", JSONObject().put("text", text).toString())
            }
        }

        override fun onClosing(webSocket: WebSocket, code: Int, reason: String) {
            webSocket.close(1000, null)
        }

        override fun onClosed(webSocket: WebSocket, code: Int, reason: String) {
            if (isCurrent(webSocket)) {
                clear(webSocket)
                emitEvent("changes.closed", JSONObject().put("code", code).toString())
            }
        }

        override fun onFailure(webSocket: WebSocket, t: Throwable, response: Response?) {
            if (isCurrent(webSocket)) {
                clear(webSocket)
                val payload = JSONObject()
                response?.let { payload.put("status", it.code) }
                emitEvent("changes.failure", payload.toString())
            }
        }
    }
}
