package com.izhaoo.gremote.media

import android.Manifest
import android.app.Activity
import android.app.AlertDialog
import android.content.pm.PackageManager
import android.media.MediaExtractor
import android.media.MediaFormat
import android.media.MediaPlayer
import android.media.MediaMetadataRetriever
import android.graphics.Bitmap
import android.view.Surface
import io.flutter.view.TextureRegistry
import java.io.ByteArrayOutputStream
import android.os.Build
import android.view.ViewGroup
import android.widget.FrameLayout
import android.widget.MediaController
import android.widget.VideoView
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.currentCoroutineContext
import kotlinx.coroutines.ensureActive
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import java.io.File
import java.io.IOException
import java.util.UUID

internal class MotionPhotoChannel(
    private val activity: Activity,
    messenger: BinaryMessenger,
    private val textures: TextureRegistry,
    private val downloadJpeg: suspend (String, String, File, String) -> Unit,
) {
    private val context = activity.applicationContext
    private val cacheDir = context.cacheDir.canonicalFile
    private val publisher = MediaStorePublisher(context)
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Main.immediate)
    private val channel = MethodChannel(messenger, "gremote/motion_photo")
    private var preview: AlertDialog? = null
    private var player: MediaPlayer? = null
    private var texture: TextureRegistry.SurfaceTextureEntry? = null
    private var playerSurface: Surface? = null

    init {
        channel.setMethodCallHandler { call, result ->
            if (call.method !in setOf("export", "exportVideo", "downloadJpeg", "transcodeM10l", "preview", "openPlayer", "playerControl", "playerStatus", "inspectVideo")) {
                result.notImplemented()
                return@setMethodCallHandler
            }
            scope.launch {
                try {
                    if (call.method == "playerControl" || call.method == "playerStatus") {
                        result.success(controlPlayer(call))
                        return@launch
                    }
                    if (call.method == "openPlayer") {
                        val movie = withContext(Dispatchers.IO) {
                            cachedInput(call.argument<String>("mp4Path")).also(::validateVideoTrack)
                        }
                        openPlayer(movie, result)
                        return@launch
                    }
                    if (call.method == "preview") {
                        val movie = withContext(Dispatchers.IO) {
                            cachedInput(call.argument<String>("mp4Path")).also(::validateVideoTrack)
                        }
                        showPreview(movie, result)
                        return@launch
                    }
                    val value: Any? = withContext(Dispatchers.IO) {
                        when (call.method) {
                            "downloadJpeg" -> {
                                downloadJpeg(
                                    requireNotNull(call.argument<String>("directory")),
                                    requireNotNull(call.argument<String>("file")),
                                    cachedOutput(call.argument<String>("jpegPath")),
                                    requireNotNull(call.argument<String>("sha256")),
                                )
                                null
                            }
                            "inspectVideo" -> inspectVideo(cachedInput(call.argument<String>("mp4Path")))
                            "exportVideo" -> {
                                checkWritePermission()
                                val video = cachedInput(call.argument<String>("mp4Path"))
                                validateVideoTrack(video)
                                val name = safeStem(call.argument<String>("displayName"))
                                currentCoroutineContext().ensureActive()
                                publisher.publishVideo(video, "${name}_${UUID.randomUUID().toString().take(8)}.mp4").toString()
                            }
                            "transcodeM10l" -> M10lTranscoder.encode(
                                cachedInput(call.argument<String>("inputPath")),
                                cachedOutput(call.argument<String>("mp4Path")),
                                call.argument<Number>("presentationTimestampUs")?.toLong(),
                            )
                            else -> export(call)
                        }
                    }
                    result.success(value)
                } catch (error: CancellationException) {
                    throw error
                } catch (error: IllegalArgumentException) {
                    result.error("invalidArgument", error.message ?: "请选择 JPEG 照片与 MP4 短片", null)
                } catch (error: SecurityException) {
                    result.error("permissionDenied", error.message ?: "无法访问文件或系统相册", null)
                } catch (_: Exception) {
                    val message = when (call.method) {
                        "downloadJpeg" -> "无法取得匹配的相机原片"
                        "transcodeM10l" -> "本机无法转换动态短片"
                        "preview" -> "本机无法播放动态短片"
                        else -> "动态照片导出失败"
                    }
                    val code = if (call.method == "export") "motionPhotoExportFailed" else "motionPhotoFailed"
                    result.error(code, message, null)
                }
            }
        }
    }

    fun close() {
        channel.setMethodCallHandler(null)
        preview?.dismiss()
        closePlayer()
        scope.cancel()
    }

    private fun closePlayer() {
        player?.release()
        player = null
        playerSurface?.release()
        playerSurface = null
        texture?.release()
        texture = null
    }

    private fun openPlayer(movie: File, result: MethodChannel.Result) {
        closePlayer()
        val entry = textures.createSurfaceTexture()
        val surface = Surface(entry.surfaceTexture())
        val next = MediaPlayer()
        texture = entry
        playerSurface = surface
        player = next
        var answered = false
        next.setSurface(surface)
        next.setOnPreparedListener {
            if (player !== next || answered) return@setOnPreparedListener
            answered = true
            entry.surfaceTexture().setDefaultBufferSize(next.videoWidth.coerceAtLeast(1), next.videoHeight.coerceAtLeast(1))
            next.isLooping = false
            result.success(mapOf("textureId" to entry.id(), "width" to next.videoWidth, "height" to next.videoHeight, "durationMs" to next.duration))
        }
        next.setOnErrorListener { _, _, _ ->
            if (!answered) {
                answered = true
                result.error("motionPhotoPreviewFailed", "本机无法播放动态短片", null)
            }
            if (player === next) closePlayer()
            true
        }
        try {
            next.setDataSource(movie.path)
            next.prepareAsync()
        } catch (error: Exception) {
            closePlayer()
            if (!answered) result.error("motionPhotoPreviewFailed", "本机无法播放动态短片", null)
        }
    }

    private fun controlPlayer(call: MethodCall): Map<String, Any> {
        val id = call.argument<Number>("textureId")?.toLong()
        require(id != null && texture?.id() == id) { "播放器已关闭，请重新打开 Live" }
        val current = requireNotNull(player)
        if (call.method == "playerControl") when (call.argument<String>("action")) {
            "play" -> current.start()
            "pause" -> current.pause()
            "seek" -> {
                val position = requireNotNull(call.argument<Number>("positionMs")).toLong()
                require(position in 0..current.duration.toLong())
                if (Build.VERSION.SDK_INT >= 26) current.seekTo(position, MediaPlayer.SEEK_CLOSEST)
                else @Suppress("DEPRECATION") current.seekTo(position.toInt())
            }
            "dispose" -> { closePlayer(); return emptyMap() }
            else -> throw IllegalArgumentException("播放器操作无效")
        }
        return mapOf("positionMs" to current.currentPosition, "playing" to current.isPlaying, "durationMs" to current.duration)
    }

    private fun inspectVideo(movie: File): Map<String, Any> {
        val retriever = MediaMetadataRetriever()
        try {
            retriever.setDataSource(movie.path)
            val duration = retriever.extractMetadata(MediaMetadataRetriever.METADATA_KEY_DURATION)?.toLong()
                ?: throw IllegalArgumentException("无法读取短片时长")
            require(duration in 1..60_000) { "短片时长无效" }
            val frames = (0..5).map { index ->
                val timeUs = (duration * 1000L * index / 5).coerceAtMost(duration * 1000 - 1)
                val frame = if (Build.VERSION.SDK_INT >= 27) retriever.getScaledFrameAtTime(timeUs, MediaMetadataRetriever.OPTION_CLOSEST, 160, 160)
                    else retriever.getFrameAtTime(timeUs, MediaMetadataRetriever.OPTION_CLOSEST)
                requireNotNull(frame) { "无法读取短片预览" }
                try {
                    ByteArrayOutputStream().use { out ->
                        frame.compress(Bitmap.CompressFormat.JPEG, 70, out)
                        out.toByteArray()
                    }
                } finally { frame.recycle() }
            }
            return mapOf("durationMs" to duration, "frames" to frames)
        } finally { retriever.release() }
    }

    private fun checkWritePermission() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.Q &&
            context.checkSelfPermission(Manifest.permission.WRITE_EXTERNAL_STORAGE) != PackageManager.PERMISSION_GRANTED
        ) throw SecurityException("请在系统设置中允许 GRemote 写入相册")
    }

    private fun safeStem(name: String?): String = name.orEmpty()
        .substringAfterLast('/').substringAfterLast('\\').substringBeforeLast('.').trim().trimStart('.').trimStart()
        .replace(Regex("[\\p{Cntrl}]"), "").take(60).trimEnd { it.isHighSurrogate() }.ifBlank { "GRemote" }

    private suspend fun export(call: MethodCall): String {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.Q &&
            context.checkSelfPermission(Manifest.permission.WRITE_EXTERNAL_STORAGE) != PackageManager.PERMISSION_GRANTED
        ) {
            throw SecurityException("请在系统设置中允许 GRemote 写入相册")
        }
        val jpeg = cachedInput(call.argument<String>("jpegPath"))
        val mp4 = cachedInput(call.argument<String>("mp4Path"))
        val stem = call.argument<String>("displayName").orEmpty()
            .substringAfterLast('/').substringAfterLast('\\')
            .substringBeforeLast('.').trim().trimStart('.').trimStart()
            .replace(Regex("[\\p{Cntrl}]"), "").take(60)
            .trimEnd { it.isHighSurrogate() }
            .ifBlank { "GRemote" }
        val id = UUID.randomUUID().toString()
        val displayName = "${stem}_${id.take(8)}_MP.jpg"
        val timestamp = call.argument<Number>("presentationTimestampUs")?.toLong()
        validateVideoTrack(mp4)
        val temp = File(cacheDir, "motion-$id.jpg")
        try {
            MotionPhotoExporter.write(jpeg, mp4, temp, timestamp)
            currentCoroutineContext().ensureActive()
            return publisher.publishMotionPhoto(temp, displayName).toString()
        } finally {
            temp.delete()
        }
    }

    private fun showPreview(mp4: File, result: MethodChannel.Result) {
        check(preview == null && !activity.isFinishing && !activity.isDestroyed)
        val player = VideoView(activity)
        val container = FrameLayout(activity)
        val height = (240 * activity.resources.displayMetrics.density).toInt()
        container.addView(player, FrameLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, height))
        val dialog = AlertDialog.Builder(activity).setTitle("动态短片")
            .setView(container).setPositiveButton("完成", null).create()
        var failed = false
        dialog.setOnDismissListener {
            player.stopPlayback()
            preview = null
            if (failed) result.error("motionPhotoPreviewFailed", "本机无法播放动态短片", null)
            else result.success(null)
        }
        player.setMediaController(MediaController(activity).apply { setAnchorView(player) })
        player.setOnPreparedListener { player.start() }
        player.setOnErrorListener { _, _, _ ->
            failed = true
            dialog.dismiss()
            true
        }
        dialog.show()
        preview = dialog
        player.setVideoPath(mp4.path)
    }

    private fun cachedInput(path: String?): File {
        val input = File(requireNotNull(path) { "请选择 JPEG 照片与 MP4 短片" }).canonicalFile
        require(input.path.startsWith(cacheDir.path + File.separator) && input.isFile) {
            "无法读取所选照片或短片"
        }
        return input
    }

    private fun cachedOutput(path: String?): File {
        val file = File(requireNotNull(path)).canonicalFile
        val parent = file.parentFile
        require(file.path.startsWith(cacheDir.path + File.separator) && parent?.isDirectory == true &&
            parent.name.startsWith("gremote-live-") && !file.exists()) { "动态照片临时位置无效" }
        return file
    }

    private fun validateVideoTrack(mp4: File) {
        val extractor = MediaExtractor()
        try {
            mp4.inputStream().use { extractor.setDataSource(it.fd) }
            val tracks = (0 until extractor.trackCount).map {
                extractor.getTrackFormat(it).getString(MediaFormat.KEY_MIME)
            }
            val primaryVideo = tracks.firstOrNull { it?.startsWith("video/") == true }
            require(primaryVideo in listOf("video/avc", "video/hevc", "video/av01")) {
                "短片需要 H.264、HEVC 或 AV1 视频轨道"
            }
            require("application/motionphoto-image-meta" !in tracks) { "请选择未配对的 MP4 短片" }
        } catch (error: IOException) {
            throw IllegalArgumentException("无法读取 MP4 短片", error)
        } finally {
            extractor.release()
        }
    }
}
