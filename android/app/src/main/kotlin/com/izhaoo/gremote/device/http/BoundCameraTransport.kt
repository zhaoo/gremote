package com.izhaoo.gremote.device.http

import android.net.Network
import android.os.SystemClock
import android.util.Log
import android.content.ContentValues
import android.content.Context
import android.os.Build
import android.os.Environment
import android.provider.MediaStore
import java.io.File
import com.izhaoo.gremote.device.NativeHttpResponse
import com.izhaoo.gremote.device.wifi.CameraProbe
import com.izhaoo.gremote.device.wifi.CameraProbeOrder
import com.izhaoo.gremote.device.wifi.CameraProbeResult
import java.io.IOException
import java.net.InetAddress
import java.util.Locale
import java.util.concurrent.TimeUnit
import kotlin.coroutines.resume
import kotlin.coroutines.resumeWithException
import kotlinx.coroutines.suspendCancellableCoroutine
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import okhttp3.Call
import okhttp3.Callback
import okhttp3.Dns
import okhttp3.Headers.Companion.toHeaders
import okhttp3.MediaType.Companion.toMediaTypeOrNull
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.RequestBody.Companion.toRequestBody
import okhttp3.Response
import okio.Buffer
import org.json.JSONArray
import org.json.JSONObject
import org.json.JSONTokener

class CameraTransportException(
    val code: String,
    message: String,
    cause: Throwable? = null,
) : Exception(message, cause)

class BoundCameraTransport(
    network: Network,
    private val context: Context,
    private val onLiveViewChunk: (ByteArray) -> Unit,
    private val emitEvent: (String, String) -> Unit,
) : CameraProbe {
    companion object {
        private const val MAX_RESPONSE_BYTES = 2L * 1024 * 1024
        private const val MAX_LIVE_VIEW_CHUNK_BYTES = 32 * 1024
    }

    @Volatile private var cameraIp = "192.168.0.1"
    @Volatile private var baseUrl: String? = null
    private val liveViewLock = Any()
    private var liveViewCall: Call? = null
    private val client = OkHttpClient.Builder()
        .socketFactory(network.socketFactory)
        .dns(object : Dns {
            override fun lookup(hostname: String): List<InetAddress> =
                if (hostname == "camera.m10v") {
                    listOf(InetAddress.getByName(cameraIp))
                } else {
                    network.getAllByName(hostname).toList()
                }
        })
        .connectTimeout(3, TimeUnit.SECONDS)
        .readTimeout(8, TimeUnit.SECONDS)
        .build()
    private val photoCalls = PhotoTransferCalls()
    private val downloadClient = client.newBuilder()
        .readTimeout(120, TimeUnit.SECONDS)
        .callTimeout(0, TimeUnit.SECONDS)
        .build()
    private val changeSocket = ChangeSocketClient(
        client = client.newBuilder().readTimeout(0, TimeUnit.SECONDS).build(),
        emitEvent = emitEvent,
    )

    suspend fun probeCamera(): String {
        val selected = CameraProbeOrder(this).findBaseUrl()
        cameraIp = selected.substringAfter("http://")
        baseUrl = selected
        return selected
    }

    override suspend fun probe(baseUrl: String): CameraProbeResult = withContext(Dispatchers.IO) {
        val request = Request.Builder().url("$baseUrl/v1/ping").get().build()
        try {
            execute(request).use { response ->
                when {
                    response.code == 404 -> CameraProbeResult.NotFound
                    !response.isSuccessful -> CameraProbeResult.InvalidResponse
                    isValidJson(readBounded(response, MAX_RESPONSE_BYTES)) ->
                        CameraProbeResult.ValidJson
                    else -> CameraProbeResult.InvalidResponse
                }
            }
        } catch (_: IOException) {
            CameraProbeResult.ConnectionFailure
        }
    }

    suspend fun request(
        method: String,
        path: String,
        headers: Map<String, String>,
        body: ByteArray?,
    ): NativeHttpResponse = withContext(Dispatchers.IO) {
        val normalizedMethod = method.uppercase(Locale.US)
        val requestBody = when {
            body != null -> body.toRequestBody(headers["Content-Type"]?.toMediaTypeOrNull())
            normalizedMethod in setOf("POST", "PUT", "PATCH") -> byteArrayOf().toRequestBody()
            else -> null
        }
        val request = Request.Builder()
            .url(resolve(path))
            .headers(headers.toHeaders())
            .method(normalizedMethod, requestBody)
            .build()

        try {
            execute(request).use { response ->
                NativeHttpResponse(
                    statusCode = response.code.toLong(),
                    headers = buildMap<String?, String?> {
                        for (index in 0 until response.headers.size) {
                            put(response.headers.name(index), response.headers.value(index))
                        }
                    },
                    body = readBounded(response, MAX_RESPONSE_BYTES),
                )
            }
        } catch (error: IOException) {
            throw CameraTransportException(
                code = "cameraRequestFailed",
                message = "Camera request failed",
                cause = error,
            )
        }
    }

    suspend fun downloadPhoto(directory: String, fileName: String): String =
        withContext(Dispatchers.IO) {
            if (!directory.matches(Regex("[A-Za-z0-9_-]+")) ||
                !fileName.matches(Regex("[A-Za-z0-9_-]+\\.(?i:JPG|JPEG|DNG)"))) {
                throw CameraTransportException("invalidCameraPath", "Invalid photo name")
            }
            val isDng = fileName.endsWith(".DNG", ignoreCase = true)
            val mime = if (isDng) "image/x-adobe-dng" else "image/jpeg"
            val path = "/v1/photos/$directory/$fileName?size=full"
            val request = Request.Builder().url(resolve(path)).get().build()
            val call = downloadClient.newCall(request)
            photoCalls.add(call)
            val started = SystemClock.elapsedRealtime()
            try {
                val response = call.execute()
                response.use {
                    if (!it.isSuccessful) {
                        throw CameraTransportException("cameraHttpStatus", "Camera returned HTTP ${it.code}")
                    }
                    val body = it.body ?: throw CameraTransportException("emptyPhoto", "Camera returned no photo")
                    if (body.contentType()?.type == "application" && body.contentType()?.subtype == "json") {
                        throw CameraTransportException("invalidPhoto", "Camera returned JSON instead of a photo")
                    }
                    val values = ContentValues().apply {
                        put(MediaStore.MediaColumns.DISPLAY_NAME, fileName)
                        put(MediaStore.MediaColumns.MIME_TYPE, mime)
                        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                            put(MediaStore.MediaColumns.RELATIVE_PATH,
                                "${Environment.DIRECTORY_PICTURES}/GRemote/${if (isDng) "DNG" else "JPEG"}")
                            put(MediaStore.MediaColumns.IS_PENDING, 1)
                        } else {
                            @Suppress("DEPRECATION")
                            val root = Environment.getExternalStoragePublicDirectory(Environment.DIRECTORY_PICTURES)
                            val folder = File(root, "GRemote/${if (isDng) "DNG" else "JPEG"}")
                            if (!folder.isDirectory && !folder.mkdirs()) {
                                throw CameraTransportException("publishFailed", "Cannot create photo directory")
                            }
                            val destination = generateSequence(0) { number -> number + 1 }
                                .map { number ->
                                    File(folder, if (number == 0) fileName else
                                        fileName.substringBeforeLast('.') + "_$number." + fileName.substringAfterLast('.'))
                                }.first { !it.exists() }
                            @Suppress("DEPRECATION")
                            put(MediaStore.MediaColumns.DATA, destination.absolutePath)
                        }
                    }
                    val resolver = context.contentResolver
                    val uri = resolver.insert(MediaStore.Images.Media.EXTERNAL_CONTENT_URI, values)
                        ?: throw CameraTransportException("publishFailed", "Cannot create media entry")
                    try {
                        val output = resolver.openOutputStream(uri)
                            ?: throw CameraTransportException("publishFailed", "Cannot open media entry")
                        var lastProgress = 0L
                        val totalBytes = body.contentLength()
                        fun reportProgress(bytes: Long) {
                            val now = SystemClock.elapsedRealtime()
                            if (bytes != 0L && bytes != totalBytes && now - lastProgress < 120) return
                            lastProgress = now
                            emitEvent("photoProgress", JSONObject().apply {
                                put("id", "$directory/$fileName")
                                put("bytes", bytes)
                                put("total", totalBytes)
                            }.toString())
                        }
                        reportProgress(0)
                        val copied = output.use { destination ->
                            body.byteStream().use { input ->
                                copyPhotoStream(input, destination, ::reportProgress)
                            }
                        }
                        if (copied <= 0L) throw CameraTransportException("emptyPhoto", "Camera returned empty photo")
                        if (body.contentLength() >= 0 && copied != body.contentLength()) {
                            throw CameraTransportException("incompletePhoto", "Camera photo transfer was incomplete")
                        }
                        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                            resolver.update(uri, ContentValues().apply {
                                put(MediaStore.MediaColumns.IS_PENDING, 0)
                            }, null, null)
                        }
                        val elapsed = (SystemClock.elapsedRealtime() - started).coerceAtLeast(1)
                        Log.i("GRemotePhotoTransfer", "format=${if (isDng) "DNG" else "JPEG"} bytes=$copied elapsedMs=$elapsed bytesPerSecond=${copied * 1000 / elapsed}")
                        uri.toString()
                    } catch (error: Throwable) {
                        resolver.delete(uri, null, null)
                        throw error
                    }
                }
            } finally {
                photoCalls.remove(call)
            }
        }

    fun startLiveView(path: String) {
        stopLiveView()
        val request = Request.Builder().url(resolve(path)).get().build()
        val call = client.newCall(request)
        synchronized(liveViewLock) { liveViewCall = call }
        call.enqueue(object : Callback {
            override fun onFailure(call: Call, e: IOException) {
                if (!call.isCanceled()) {
                    emitEvent("liveView", "{\"state\":\"failed\"}")
                }
                clearLiveViewCall(call)
            }

            override fun onResponse(call: Call, response: Response) {
                response.use {
                    if (!response.isSuccessful) {
                        emitEvent(
                            "liveView",
                            "{\"state\":\"failed\",\"status\":${response.code}}",
                        )
                        clearLiveViewCall(call)
                        return
                    }
                    val stream = response.body?.byteStream() ?: run {
                        clearLiveViewCall(call)
                        return
                    }
                    val buffer = ByteArray(MAX_LIVE_VIEW_CHUNK_BYTES)
                    while (!call.isCanceled()) {
                        val count = stream.read(buffer)
                        if (count < 0) break
                        if (count > 0) onLiveViewChunk(buffer.copyOf(count))
                    }
                }
                clearLiveViewCall(call)
                if (!call.isCanceled()) {
                    emitEvent("liveView", "{\"state\":\"ended\"}")
                }
            }
        })
    }

    fun stopLiveView() {
        val call = synchronized(liveViewLock) {
            liveViewCall.also { liveViewCall = null }
        }
        call?.cancel()
        if (call != null) {
            emitEvent("liveView", "{\"state\":\"stopped\"}")
        }
    }

    fun openChangeSocket(path: String) {
        changeSocket.open(resolve(path).replaceFirst("http://", "ws://"))
    }

    fun closeChangeSocket() = changeSocket.close()

    fun close() {
        photoCalls.close()
        stopLiveView()
        changeSocket.close()
        client.dispatcher.cancelAll()
        client.connectionPool.evictAll()
        client.dispatcher.executorService.shutdown()
    }

    private fun resolve(path: String): String {
        if (!path.startsWith('/') || "://" in path) {
            throw CameraTransportException(
                code = "invalidCameraPath",
                message = "Camera URL must be a relative path",
            )
        }
        val root = baseUrl ?: throw CameraTransportException(
            code = "wifiNotConnected",
            message = "Camera endpoint has not been probed",
        )
        return "$root$path"
    }

    private suspend fun execute(request: Request): Response =
        suspendCancellableCoroutine { continuation ->
            val call = client.newCall(request)
            continuation.invokeOnCancellation { call.cancel() }
            call.enqueue(object : Callback {
                override fun onFailure(call: Call, e: IOException) {
                    if (continuation.isActive) continuation.resumeWithException(e)
                }

                override fun onResponse(call: Call, response: Response) {
                    if (continuation.isActive) {
                        continuation.resume(response)
                    } else {
                        response.close()
                    }
                }
            })
        }

    private fun readBounded(response: Response, maxBytes: Long): ByteArray {
        val body = response.body ?: return byteArrayOf()
        if (body.contentLength() > maxBytes) {
            throw CameraTransportException(
                code = "cameraResponseTooLarge",
                message = "Camera response exceeds the size limit",
            )
        }
        val output = Buffer()
        val source = body.source()
        var total = 0L
        while (true) {
            val count = source.read(output, minOf(8_192L, maxBytes + 1 - total))
            if (count < 0) break
            total += count
            if (total > maxBytes) {
                throw CameraTransportException(
                    code = "cameraResponseTooLarge",
                    message = "Camera response exceeds the size limit",
                )
            }
        }
        return output.readByteArray()
    }

    private fun isValidJson(bytes: ByteArray): Boolean = runCatching {
        when (JSONTokener(bytes.toString(Charsets.UTF_8)).nextValue()) {
            is JSONObject, is JSONArray -> true
            else -> false
        }
    }.getOrDefault(false)

    private fun clearLiveViewCall(call: Call) {
        synchronized(liveViewLock) {
            if (liveViewCall === call) liveViewCall = null
        }
    }
}
