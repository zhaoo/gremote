package com.izhaoo.gremote.imaging

/** One render in flight, one replaceable pending request, no UI-thread waits. */
class GpuFrameScheduler<T, R>(
    private val post: (() -> Unit) -> Unit,
    private val render: (T) -> R,
    private val emit: (Long, R) -> Unit,
    private val error: (Long, Throwable) -> Unit,
) {
    private data class Job<T>(val generation: Long, val value: T)
    private val lock = Any()
    private var pending: Job<T>? = null
    private var latest = 0L
    private var scheduled = false
    private var closed = false

    fun submit(generation: Long, value: T): Boolean {
        val schedule = synchronized(lock) {
            if (closed || generation <= latest) return false
            latest = generation
            pending = Job(generation, value)
            if (scheduled) false else { scheduled = true; true }
        }
        if (schedule) post(::drain)
        return true
    }

    fun invalidate(generation: Long): Boolean = synchronized(lock) {
        if (closed || generation <= latest) return false
        latest = generation
        pending = null
        true
    }

    fun isCurrent(generation: Long): Boolean = synchronized(lock) {
        !closed && generation == latest
    }

    fun close() = synchronized(lock) { closed = true; pending = null }

    private fun drain() {
        while (true) {
            val job = synchronized(lock) {
                if (closed || pending == null) { scheduled = false; return }
                pending!!.also { pending = null }
            }
            try {
                val result = render(job.value)
                if (isCurrent(job.generation)) emit(job.generation, result)
            } catch (failure: Throwable) {
                if (isCurrent(job.generation)) error(job.generation, failure)
            }
        }
    }
}
