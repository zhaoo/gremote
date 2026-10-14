package com.izhaoo.gremote.device.http
import okhttp3.OkHttpClient
import okhttp3.Request
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test
class PhotoTransferCallsTest {
    private val client = OkHttpClient()
    private fun call() = client.newCall(Request.Builder().url("http://127.0.0.1/v1/photos/a/b.JPG").build())
    @Test fun disconnectCancelsActiveSynchronousDownloads() {
        val calls = PhotoTransferCalls()
        val active = call()
        val completed = call()
        calls.add(active)
        calls.add(completed)
        calls.remove(completed)
        calls.close()
        assertTrue(active.isCanceled())
        assertFalse(completed.isCanceled())
    }
    @Test fun racingDownloadAfterDisconnectIsImmediatelyCancelled() {
        val calls = PhotoTransferCalls()
        calls.close()
        val racing = call()
        calls.add(racing)
        assertTrue(racing.isCanceled())
    }
}
