package com.izhaoo.gremote.media

import android.Manifest
import android.app.Activity
import android.app.AlertDialog
import android.content.pm.PackageManager
import android.media.MediaExtractor
import android.media.MediaFormat
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
    private val downloadJpeg: suspend (String, String, File, String) -> Unit,
) {
    private val context = activity.applicationContext
    private val cacheDir = context.cacheDir.canonicalFile
    private val publisher = MediaStorePublisher(context)
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Main.immediate)
    private val channel = MethodChannel(messenger, "gremote/motion_photo")
    private var preview: AlertDialog? = null

    init {
        channel.setMethodCallHandler { call, result ->
            if (call.method !in setOf("export", "downloadJpeg", "transcodeM10l", "preview")) {
                result.notImplemented()
                return@setMethodCallHandler
            }
            scope.launch {
                try {
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
        scope.cancel()
    }

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
