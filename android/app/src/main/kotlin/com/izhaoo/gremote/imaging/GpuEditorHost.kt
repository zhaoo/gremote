package com.izhaoo.gremote.imaging

import android.os.Handler
import android.os.HandlerThread
import android.os.Looper
import android.os.ParcelFileDescriptor
import android.view.Surface
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.view.TextureRegistry
import org.json.JSONObject

/** Resident native EGL renderer. The platform thread never waits for GPU work. */
class GpuEditorHost(messenger: BinaryMessenger, private val textures: TextureRegistry) {
    private val channel = MethodChannel(messenger, "gremote/gpu_editor")
    private val main = Handler(Looper.getMainLooper())
    private val thread = HandlerThread("GRemotePhotoGPU").apply { start() }
    private val worker = Handler(thread.looper)
    private val sessions = mutableMapOf<Long, Session>() // platform thread only
    private val nativeHandles = mutableSetOf<Long>() // render thread only
    private var pendingOpens = 0
    @Volatile private var closed = false
    @Volatile private var paused = false

    init { channel.setMethodCallHandler(::handle) }

    private data class Request(val generation: Long, val parameters: FloatArray,
        val lutKey: String, val strength: Float, val width: Int, val height: Int)
    private data class SurfaceSpec(val surface: Surface, val width: Int, val height: Int)

    private inner class Session(val id: Long, val producer: TextureRegistry.SurfaceProducer,
        val sourceWidth: Int, val sourceHeight: Int) {
        @Volatile var disposed = false
        @Volatile var hasSurface = false
        @Volatile var latest = 0L
        private var outputWidth = sourceWidth
        private var outputHeight = sourceHeight
        private val surface = GpuSurfaceLifecycle<SurfaceSpec>(
            post = { worker.post(it) },
            attach = { spec ->
                try {
                    GpuNativeBridge.attach(id, spec.surface, spec.width, spec.height)
                    if (!paused && GpuNativeBridge.present(id, latest)) publish(latest)
                } catch (failure: Throwable) { hasSurface = false; report(latest, failure) }
            },
            detach = {
                if (nativeHandles.contains(id)) {
                    try { GpuNativeBridge.detach(id) } catch (failure: Throwable) { report(latest, failure) }
                }
            },
            release = {
                try { closeNative(id) } finally { main.post { releaseProducer(producer) } }
            },
        )
        private val scheduler: GpuFrameScheduler<Request, Boolean> = GpuFrameScheduler(
            post = { worker.post(it) },
            render = { request -> GpuNativeBridge.render(id, request.generation,
                request.parameters, request.lutKey, request.strength, request.width, request.height) },
            emit = { generation, rendered ->
                if (rendered && !paused && hasSurface && !disposed) {
                    try {
                        if (GpuNativeBridge.present(id, generation)) publish(generation)
                    } catch (failure: Throwable) { hasSurface = false; report(generation, failure) }
                }
            },
            error = ::report,
        )
        private fun schedulerCurrent(generation: Long): Boolean = scheduler.isCurrent(generation)
        private fun publish(generation: Long) {
            main.post {
                if (!disposed && !closed && !paused && schedulerCurrent(generation)) {
                    producer.scheduleFrame()
                    channel.invokeMethod("frame", mapOf("sessionId" to id,
                        "generation" to generation, "width" to outputWidth, "height" to outputHeight))
                }
            }
        }
        init {
            producer.setSize(sourceWidth, sourceHeight)
            producer.setCallback(object : TextureRegistry.SurfaceProducer.Callback {
                override fun onSurfaceCreated() { main.post { attachSurface() } }
                override fun onSurfaceDestroyed() { main.post {
                    if (!disposed) { hasSurface = false; surface.destroyed() }
                } }
            })
            attachSurface()
        }
        fun attachSurface() {
            if (disposed || closed || paused) return
            try {
                val value = producer.surface
                if (value.isValid) {
                    hasSurface = true
                    // Keep the producer allocation stable across crop/ratio drags.
                    // The frame's logical aspect travels with its generation.
                    surface.created(SurfaceSpec(value, sourceWidth, sourceHeight))
                } else { hasSurface = false; throw IllegalStateException("gpuSurfaceNotReady") }
            } catch (failure: Throwable) { report(latest, failure) }
        }
        fun update(request: Request): Boolean {
            if (disposed || request.generation <= latest) return false
            if (!GpuNativeBridge.advance(id, request.generation)) return false
            latest = request.generation
            outputWidth = request.width; outputHeight = request.height
            if (!hasSurface && !paused) attachSurface()
            return scheduler.submit(request.generation, request)
        }
        fun invalidate(generation: Long): Boolean {
            if (disposed || generation <= latest) return false
            if (!GpuNativeBridge.advance(id, generation)) return false
            latest = generation
            return scheduler.invalidate(generation)
        }
        private fun report(generation: Long, failure: Throwable) {
            main.post {
                if (!disposed && !closed && !paused && generation == latest) {
                    channel.invokeMethod("error", mapOf("sessionId" to id,
                        "generation" to generation, "code" to "gpuPreviewFailed",
                        "message" to "预览失败，请重试", "detail" to failure.message))
                }
            }
        }
        fun pause() { if (!disposed) { hasSurface = false; surface.destroyed() } }
        fun close() {
            if (disposed) return
            disposed = true; hasSurface = false
            scheduler.close(); GpuNativeBridge.revoke(id)
            producer.setCallback(null)
            surface.close()
        }
    }

    private fun releaseProducer(producer: TextureRegistry.SurfaceProducer) {
        try { producer.release() } catch (_: RuntimeException) {
            // Flutter may already have disposed its texture registry on engine teardown.
        }
    }
    private fun closeNative(id: Long) {
        if (nativeHandles.remove(id)) GpuNativeBridge.close(id)
    }
    private fun handle(call: MethodCall, result: MethodChannel.Result) {
        if (closed) { result.error("gpuClosed", "图像处理已关闭", null); return }
        try {
            val args = call.arguments as? Map<*, *> ?: emptyMap<Any, Any>()
            when (call.method) {
                "open" -> open(args, result)
                "prepareLut" -> {
                    val id = (args["sessionId"] as? Number)?.toLong()
                    val session = sessions[id] ?: throw IllegalArgumentException("invalidSession")
                    val key = args["key"] as? String ?: throw IllegalArgumentException("lutKey")
                    val bytes = args["bytes"] as? ByteArray ?: throw IllegalArgumentException("lutBytes")
                    require(key.isNotEmpty() && key.length <= 128 && bytes.size in 1..16*1024*1024)
                    worker.post {
                        try {
                            if (session.disposed) throw IllegalStateException("gpuSessionClosed")
                            GpuNativeBridge.prepareLut(session.id, key, bytes)
                            main.post { result.success(null) }
                        } catch (failure: Throwable) {
                            main.post { result.error("gpuLutFailed", "无法读取 LUT", failure.message) }
                        }
                    }
                }
                "update" -> {
                    val id = (args["sessionId"] as? Number)?.toLong()
                    val session = sessions[id] ?: throw IllegalArgumentException("invalidSession")
                    val generation = (args["generation"] as? Number)?.toLong() ?: 0
                    val parameters = args["parameters"] as? FloatArray ?: throw IllegalArgumentException("parameters")
                    val strength = (args["strength"] as? Number)?.toFloat() ?: 1f
                    val width = (args["width"] as? Number)?.toInt() ?: 0
                    val height = (args["height"] as? Number)?.toInt() ?: 0
                    val lutKey = args["lutKey"] as? String ?: ""
                    require(parameters.size == 1062 && parameters.all { it.isFinite() })
                    require(generation > 0 && strength.isFinite() && strength in 0f..1f)
                    require(width > 0 && height > 0 && width.toLong() * height <= 8L * 1024 * 1024)
                    require(lutKey.length <= 128)
                    result.success(session.update(Request(generation, parameters.copyOf(), lutKey, strength, width, height)))
                }
                "invalidate" -> {
                    val session = sessions[(args["sessionId"] as? Number)?.toLong()]
                        ?: throw IllegalArgumentException("invalidSession")
                    result.success(session.invalidate((args["generation"] as? Number)?.toLong() ?: 0))
                }
                "close" -> {
                    sessions.remove((args["sessionId"] as? Number)?.toLong())?.close()
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        } catch (failure: Throwable) {
            result.error("gpuInvalidRequest", "无法处理图像请求", failure.message)
        }
    }
    private fun open(args: Map<*, *>, result: MethodChannel.Result) {
        val fd = (args["fd"] as? Number)?.toInt() ?: throw IllegalArgumentException("fd")
        require(fd >= 0)
        // Borrow the channel FD; the Dart owner closes its original in finally.
        // The duplicate is consumed by native decoding even if initialization fails.
        val descriptor = ParcelFileDescriptor.fromFd(fd)
        try {
            val orientation = (args["orientation"] as? Number)?.toInt() ?: 1
            val maxEdge = (args["maxEdge"] as? Number)?.toInt() ?: 1600
            require(orientation in 1..8 && maxEdge in 64..4096)
            require(sessions.size + pendingOpens < 2)
            ++pendingOpens
            worker.post {
                var id = 0L
                try {
                    id = GpuNativeBridge.create(descriptor.detachFd(), orientation, maxEdge)
                    nativeHandles.add(id)
                    val info = JSONObject(GpuNativeBridge.info(id))
                    val width = info.getInt("sourceWidth"); val height = info.getInt("sourceHeight")
                    main.post {
                        --pendingOpens
                        if (closed) { result.error("gpuClosed", "图像处理已关闭", null) }
                        else {
                            var allocated: TextureRegistry.SurfaceProducer? = null
                            try {
                                val producer = textures.createSurfaceProducer()
                                allocated = producer
                                val session = Session(id, producer, width, height)
                                sessions[id] = session
                                result.success(mapOf("sessionId" to id, "textureId" to producer.id(),
                                    "sourceWidth" to width, "sourceHeight" to height,
                                    "capabilities" to info.getJSONObject("capabilities").toString()))
                            } catch (failure: Throwable) {
                                allocated?.setCallback(null)
                                allocated?.let(::releaseProducer)
                                worker.post { closeNative(id) }
                                result.error("gpuSurfaceUnavailable", "无法打开照片预览", failure.message)
                            }
                        }
                    }
                } catch (failure: Throwable) {
                    if (id != 0L) closeNative(id)
                    main.post { --pendingOpens; result.error("gpuUnavailable", "无法打开照片预览", failure.message) }
                } finally { descriptor.close() }
            }
        } catch (failure: Throwable) { descriptor.close(); throw failure }
    }
    fun onPause() { paused = true; sessions.values.forEach { it.pause() } }
    fun onResume() { paused = false; sessions.values.forEach { it.attachSurface() } }
    fun close() {
        if (closed) return
        closed = true; channel.setMethodCallHandler(null)
        sessions.values.forEach { it.close() }; sessions.clear()
        // Handles created by an in-flight open are tracked on this same queue,
        // so cleanup includes them even if the platform callback has not run.
        worker.post {
            try {
                nativeHandles.toList().forEach { id -> try { closeNative(id) } catch (_: Throwable) {} }
            } finally { thread.quitSafely() }
        }
    }
}
