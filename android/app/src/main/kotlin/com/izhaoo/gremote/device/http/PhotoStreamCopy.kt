package com.izhaoo.gremote.device.http
import java.io.InputStream
import java.io.OutputStream
internal fun copyPhotoStream(input: InputStream, output: OutputStream): Long = input.copyTo(output, bufferSize = 64 * 1024)
