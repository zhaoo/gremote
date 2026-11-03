package com.izhaoo.gremote.imaging

import android.view.Surface

/** All GL calls run on GpuEditorHost's owner thread. advance/revoke are atomic. */
internal object GpuNativeBridge {
    init { System.loadLibrary("gremote_imaging") }
    external fun create(fd: Int, orientation: Int, maxEdge: Int): Long
    external fun info(id: Long): String
    external fun advance(id: Long, generation: Long): Boolean
    external fun revoke(id: Long)
    external fun prepareLut(id: Long, key: String, bytes: ByteArray)
    external fun render(id: Long, generation: Long, parameters: FloatArray,
        lutKey: String, strength: Float, width: Int, height: Int): Boolean
    external fun attach(id: Long, surface: Surface, width: Int, height: Int)
    external fun detach(id: Long)
    external fun present(id: Long, generation: Long): Boolean
    external fun close(id: Long)
}
