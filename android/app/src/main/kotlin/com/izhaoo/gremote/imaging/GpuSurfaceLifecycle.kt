package com.izhaoo.gremote.imaging

/** A queued Surface callback is valid only for the latest surface lease. */
class GpuSurfaceLifecycle<S>(
    private val post: (() -> Unit) -> Unit,
    private val attach: (S) -> Unit,
    private val detach: () -> Unit,
    private val release: () -> Unit,
) {
    private val lock = Any()
    private var serial = 0L
    private var closed = false
    fun created(surface: S) {
        val token = synchronized(lock) { if (closed) return; ++serial }
        post { if (valid(token)) attach(surface) }
    }
    fun destroyed() {
        val token = synchronized(lock) { if (closed) return; ++serial }
        post { if (valid(token)) detach() }
    }
    fun close() {
        synchronized(lock) { if (closed) return; closed = true; ++serial }
        post { try { detach() } finally { release() } }
    }
    private fun valid(token: Long) = synchronized(lock) { !closed && token == serial }
}
