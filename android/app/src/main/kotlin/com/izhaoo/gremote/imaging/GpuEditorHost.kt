package com.izhaoo.gremote.imaging

import androidx.exifinterface.media.ExifInterface
import com.izhaoo.gremote.media.SourceColorPolicy
import kotlin.math.roundToInt
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
        val sourceWidth: Int, val sourceHeight: Int, val previewWidth: Int, val previewHeight: Int) {
        @Volatile var disposed = false
        @Volatile var hasSurface = false
        @Volatile var latest = 0L
        @Volatile var comparing = false
        private var outputWidth = sourceWidth
        private var outputHeight = sourceHeight
        private val surface = GpuSurfaceLifecycle<SurfaceSpec>(
            post = { worker.post(it) },
            attach = { spec ->
                try {
                    GpuNativeBridge.attach(id, spec.surface, spec.width, spec.height)
                    val original = comparing
                    if (!paused && GpuNativeBridge.present(id, latest, original)) publish(latest, original)
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
                        val original = comparing
                        if (GpuNativeBridge.present(id, generation, original)) publish(generation, original)
                    } catch (failure: Throwable) { hasSurface = false; report(generation, failure) }
                }
            },
            error = ::report,
        )
        private fun schedulerCurrent(generation: Long): Boolean = scheduler.isCurrent(generation)
        private fun publish(generation: Long, original: Boolean) {
            main.post {
                if (!disposed && !closed && !paused && schedulerCurrent(generation) && original == comparing) {
                    producer.scheduleFrame()
                    channel.invokeMethod("frame", mapOf("sessionId" to id,
                        "generation" to generation, "width" to if (original) sourceWidth else outputWidth, "height" to if (original) sourceHeight else outputHeight, "original" to original))
                }
            }
        }
        init {
            producer.setSize(previewWidth, previewHeight)
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
                    surface.created(SurfaceSpec(value, previewWidth, previewHeight))
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
        fun compare(original: Boolean) {
            comparing = original
            worker.post { try { if (!disposed && !paused && hasSurface && GpuNativeBridge.present(id, latest, original)) publish(latest, original) } catch (failure: Throwable) { report(latest, failure) } }
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
                "export" -> export(args, result)
                "cancelExport" -> { GpuNativeBridge.cancelExport((args["jobId"] as Number).toLong()); result.success(null) }
                "compare" -> {
                    val session=sessions[(args["sessionId"] as Number).toLong()] ?: throw IllegalArgumentException("invalidSession")
                    session.compare(args["original"] == true);result.success(null)
                }
                "histogram", "thumbnail" -> {
                    val session=sessions[(args["sessionId"] as Number).toLong()] ?: throw IllegalArgumentException("invalidSession")
                    worker.post {
                        try {
                            if(session.disposed)throw IllegalStateException("gpuSessionClosed")
                            val data = if(call.method == "histogram") GpuNativeBridge.histogram(session.id,(args["generation"] as Number).toLong())
                                else GpuNativeBridge.thumbnail(session.id,args["parameters"] as FloatArray,args["cube"] as? ByteArray,(args["strength"] as Number).toFloat(),(args["width"] as Number).toInt(),(args["height"] as Number).toInt())
                            main.post {result.success(data)}
                        } catch(failure: Throwable) {main.post { result.error("gpuAnalysisFailed","无法读取预览",failure.message) }}
                    }
                }
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
    private fun export(args: Map<*, *>, result: MethodChannel.Result) {
        val jobId = (args["jobId"] as Number).toLong()
        val descriptor = ParcelFileDescriptor.fromFd((args["fd"] as Number).toInt())
        try {
            val id = (args["sessionId"] as? Number)?.toLong() ?: 0L
            val orientation = (args["orientation"] as Number).toInt()
            val parameters = args["parameters"] as FloatArray
            val geometry = (args["geometry"] as IntArray)
            val rectangles = args["rectangles"] as IntArray
            val images = (args["images"] as List<*>).map { it as ByteArray }.toTypedArray()
            val cube = args["cube"] as? ByteArray
            val strength = (args["strength"] as Number).toFloat()
            val path = args["path"] as String
            require(orientation in 1..8 && parameters.size == 1062 && geometry.size == 8)
            require(id == 0L || sessions.containsKey(id))
            GpuNativeBridge.createExport(jobId)
            worker.post {
                try {
                    if (closed) throw IllegalStateException("cancelled")
                    val exif = ExifInterface(descriptor.fileDescriptor)
                    val adobe = SourceColorPolicy.isAdobeRgb(exif.getAttributeInt(ExifInterface.TAG_COLOR_SPACE, 1), exif.getAttribute("InteroperabilityIndex"))
                    GpuNativeBridge.exportJpeg(jobId, id, descriptor.detachFd(), orientation, adobe, args["viewport"] == true, parameters, cube, strength, geometry, images, rectangles, path)
                    main.post { result.success(null) }
                } catch (failure: Throwable) {
                    main.post { result.error(if (failure.message == "cancelled") "cancelled" else "gpuExportFailed", "导出失败", failure.message) }
                } finally { descriptor.close(); GpuNativeBridge.finishExport(jobId) }
            }
        } catch (failure: Throwable) { descriptor.close(); throw failure }
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
            val version = (args["processVersion"] as? Number)?.toInt() ?: 2
            require(version in 1..2)
            require(orientation in 1..8 && maxEdge in 64..4096)
            require(sessions.size + pendingOpens < 2)
            ++pendingOpens
            worker.post {
                var id = 0L
                try {
                    val exif = ExifInterface(descriptor.fileDescriptor)
                    val adobe = SourceColorPolicy.isAdobeRgb(exif.getAttributeInt(ExifInterface.TAG_COLOR_SPACE, 1), exif.getAttribute("InteroperabilityIndex"))
                    id = GpuNativeBridge.create(descriptor.detachFd(), orientation, maxEdge, version, adobe)
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
                                val scale = minOf(1.0, maxEdge.toDouble() / maxOf(width, height))
                                val session = Session(id, producer, width, height, maxOf(1, (width*scale).roundToInt()), maxOf(1, (height*scale).roundToInt()))
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
    fun onTrimMemory(level: Int) {
        if(level < 15 || level == 20)return
        sessions.values.toList().forEach { session ->
            channel.invokeMethod("invalidated",mapOf("sessionId" to session.id));session.close()
        }
        sessions.clear()
    }
    fun close() {
        if (closed) return
        closed = true; channel.setMethodCallHandler(null)
        GpuNativeBridge.cancelExports()
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
