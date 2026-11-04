package com.izhaoo.gremote.device.http

import com.izhaoo.gremote.device.NativeHttpResponse
import java.util.concurrent.TimeUnit
import java.net.Proxy
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.RequestBody.Companion.toRequestBody
import okio.Buffer

/** Only constructed from the already probed camera transport, on its Network. */
class BoundCompanionTransport internal constructor(
    client: OkHttpClient,
    private val host: String,
    private val isCurrent: () -> Boolean,
) {
    private val client = client.newBuilder().proxy(Proxy.NO_PROXY).followRedirects(false).followSslRedirects(false)
        .connectTimeout(1500, TimeUnit.MILLISECONDS).readTimeout(1500, TimeUnit.MILLISECONDS)
        .callTimeout(2, TimeUnit.SECONDS).build()
    private fun invalid(): Nothing = throw CameraTransportException("invalidCompanionTarget", "无效伴侣请求目标")
    suspend fun request(method: String, path: String, headers: Map<String, String>, body: ByteArray?): NativeHttpResponse = withContext(Dispatchers.IO) {
        if (!host.matches(Regex("(?:[0-9]{1,3}\\.){3}[0-9]{1,3}")) || host.split('.').any { it.toInt() > 255 }) invalid()
        if (method !in setOf("GET", "POST", "PUT") || !path.matches(Regex("/m10v/v1/(?:hotspot|capabilities|state|extensions/(?:capabilities|state|operations(?:/[a-f0-9]{32})?)|operations(?:/[a-f0-9]{32})?|films/stage(?:/[a-f0-9]{32}(?:/(?:verify|chunks/[0-2]))?)?)"))) invalid()
        if (path == "/m10v/v1/hotspot" &&
            (host != "192.168.0.1" || method != "GET" || headers != mapOf("X-M10V-Hotspot" to "1"))) invalid()
        val allowed = setOf("x-m10v-hotspot", "x-m10v-keyid", "x-m10v-nonce", "x-m10v-boot", "x-m10v-session", "x-m10v-seq", "x-m10v-signature", "x-m10v-chunk-hash", "content-type")
        if (headers.size > 8 || headers.keys.map { it.lowercase() }.toSet().size != headers.size || headers.any { it.key.lowercase() !in allowed || it.value.length > 80 || it.value.any { c -> c.code < 32 || c.code > 126 } } || (body?.size ?: 0) > 16384 || (method == "GET" && (body != null && body.isNotEmpty()))) invalid()
        if (!isCurrent()) throw CameraTransportException("companionSessionChanged", "相机连接已变化")
        val builder = Request.Builder().url("http://$host:18743$path")
        headers.forEach { (key, value) -> builder.header(key, value) }
        builder.method(method, if (method == "GET") null else (body ?: byteArrayOf()).toRequestBody())
        client.newCall(builder.build()).execute().use { response ->
            if (!isCurrent()) throw CameraTransportException("companionSessionChanged", "相机连接已变化")
            if (response.code in 300..399) invalid()
            val bytes = Buffer()
            response.body?.let { responseBody ->
                if (responseBody.contentLength() > 16384) throw CameraTransportException("companionResponseTooLarge", "伴侣响应超限")
                val source = responseBody.source()
                while (true) {
                    val count = source.read(bytes, 16385 - bytes.size)
                    if (bytes.size > 16384) throw CameraTransportException("companionResponseTooLarge", "伴侣响应超限")
                    if (count < 0) break
                }
            }
            if (!isCurrent()) throw CameraTransportException("companionSessionChanged", "相机连接已变化")
            val resultHeaders = mutableMapOf<String?, String?>()
            for (name in response.headers.names()) {
                val values = response.headers.values(name)
                if (name.lowercase().startsWith("x-m10v-") && values.size != 1) invalid()
                resultHeaders[name.lowercase()] = values.joinToString(",")
            }
            NativeHttpResponse(response.code.toLong(), resultHeaders, bytes.readByteArray())
        }
    }
}
