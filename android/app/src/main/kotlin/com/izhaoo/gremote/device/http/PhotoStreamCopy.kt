package com.izhaoo.gremote.device.http

import java.io.InputStream
import java.io.OutputStream

internal fun copyPhotoStream(
    input: InputStream,
    output: OutputStream,
    onProgress: (Long) -> Unit = {},
): Long {
    val buffer = ByteArray(64 * 1024)
    var copied = 0L
    while (true) {
        val count = input.read(buffer)
        if (count < 0) break
        if (count == 0) continue
        output.write(buffer, 0, count)
        copied += count
        onProgress(copied)
    }
    return copied
}
