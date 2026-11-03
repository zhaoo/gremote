package com.izhaoo.gremote.imaging

import android.view.Surface

/** All GL calls run on GpuEditorHost's owner thread. advance/revoke are atomic. */
internal object GpuNativeBridge {
    init { System.loadLibrary("gremote_imaging") }
    external fun create(fd: Int, orientation: Int, maxEdge: Int, processVersion: Int, adobeRgb: Boolean): Long
    external fun createExport(jobId: Long)
    external fun cancelExport(jobId: Long)
    external fun cancelExports()
    external fun finishExport(jobId: Long)
    external fun exportJpeg(jobId: Long, id: Long, fd: Int, orientation: Int, adobeRgb: Boolean, viewport: Boolean, parameters: FloatArray, cube: ByteArray?, strength: Float, geometry: IntArray, images: Array<ByteArray>, rectangles: IntArray, path: String)
    external fun info(id: Long): String
    external fun advance(id: Long, generation: Long): Boolean
    external fun revoke(id: Long)
    external fun prepareLut(id: Long, key: String, bytes: ByteArray)
    external fun render(id: Long, generation: Long, parameters: FloatArray,
        lutKey: String, strength: Float, width: Int, height: Int): Boolean
    external fun attach(id: Long, surface: Surface, width: Int, height: Int)
    external fun detach(id: Long)
    external fun present(id: Long, generation: Long, original: Boolean = false): Boolean
    external fun histogram(id: Long, generation: Long): FloatArray?
    external fun thumbnail(id: Long, parameters: FloatArray, cube: ByteArray?, strength: Float, width: Int, height: Int): ByteArray
    external fun close(id: Long)
}
